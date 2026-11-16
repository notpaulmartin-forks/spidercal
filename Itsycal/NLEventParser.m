//
//  NLEventParser.m
//  Spidercal
//

#import "NLEventParser.h"
#import "Itsycal.h"

@implementation NLEventDraft
@end

NSString *ShortTimeZoneName(NSTimeZone *timeZone, NSDate *date)
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"z";
    formatter.timeZone = timeZone;
    NSArray<NSLocale *> *locales = @[NSLocale.currentLocale,
                                     [NSLocale localeWithLocaleIdentifier:@"en_US"],
                                     [NSLocale localeWithLocaleIdentifier:@"en_GB"],
                                     [NSLocale localeWithLocaleIdentifier:@"en_AU"],
                                     [NSLocale localeWithLocaleIdentifier:@"en_IN"],
                                     [NSLocale localeWithLocaleIdentifier:@"ja_JP"]];
    for (NSLocale *locale in locales) {
        formatter.locale = locale;
        NSString *name = [formatter stringFromDate:date];
        if (name.length && ![name hasPrefix:@"GMT"] && ![name hasPrefix:@"UTC"]) return name;
    }
    return [timeZone abbreviationForDate:date];
}

// Country code -> the time zone most people there mean.
static NSDictionary<NSString *, NSString *> *CountryZones(void)
{
    static NSDictionary *zones;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zones = @{
            @"DE": @"Europe/Berlin",    @"UK": @"Europe/London",   @"GB": @"Europe/London",
            @"FR": @"Europe/Paris",     @"ES": @"Europe/Madrid",   @"IT": @"Europe/Rome",
            @"NL": @"Europe/Amsterdam", @"BE": @"Europe/Brussels", @"CH": @"Europe/Zurich",
            @"AT": @"Europe/Vienna",    @"PL": @"Europe/Warsaw",   @"SE": @"Europe/Stockholm",
            @"NO": @"Europe/Oslo",      @"DK": @"Europe/Copenhagen", @"FI": @"Europe/Helsinki",
            @"IE": @"Europe/Dublin",    @"PT": @"Europe/Lisbon",   @"GR": @"Europe/Athens",
            @"CZ": @"Europe/Prague",    @"HU": @"Europe/Budapest", @"RO": @"Europe/Bucharest",
            @"TR": @"Europe/Istanbul",  @"UA": @"Europe/Kyiv",     @"IL": @"Asia/Jerusalem",
            @"AE": @"Asia/Dubai",       @"IN": @"Asia/Kolkata",    @"SG": @"Asia/Singapore",
            @"HK": @"Asia/Hong_Kong",   @"CN": @"Asia/Shanghai",   @"JP": @"Asia/Tokyo",
            @"KR": @"Asia/Seoul",       @"TH": @"Asia/Bangkok",    @"ID": @"Asia/Jakarta",
            @"AU": @"Australia/Sydney", @"NZ": @"Pacific/Auckland",
            @"ZA": @"Africa/Johannesburg", @"EG": @"Africa/Cairo", @"NG": @"Africa/Lagos",
            @"KE": @"Africa/Nairobi",
            @"US": @"America/New_York", @"CA": @"America/Toronto", @"MX": @"America/Mexico_City",
            @"BR": @"America/Sao_Paulo", @"AR": @"America/Argentina/Buenos_Aires",
            @"CL": @"America/Santiago", @"CO": @"America/Bogota",
        };
    });
    return zones;
}

// Lowercased city and country names -> time zone name.
static NSDictionary<NSString *, NSString *> *NamedZones(void)
{
    static NSDictionary *named;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *d = [NSMutableDictionary new];
        // Cities: the last part of each zone name, e.g. "new york".
        for (NSString *zone in [NSTimeZone knownTimeZoneNames]) {
            NSString *city = [[zone lastPathComponent] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            d[city.lowercaseString] = zone;
        }
        // Countries, in English and in the user's language.
        NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        [CountryZones() enumerateKeysAndObjectsUsingBlock:^(NSString *code, NSString *zone, BOOL *stop) {
            NSString *isoCode = [code isEqualToString:@"UK"] ? @"GB" : code;
            for (NSLocale *locale in @[english, NSLocale.currentLocale]) {
                NSString *country = [locale localizedStringForCountryCode:isoCode];
                if (country.length) d[country.lowercaseString] = zone;
            }
        }];
        d[@"uk"] = @"Europe/London";
        d[@"britain"] = @"Europe/London";
        d[@"england"] = @"Europe/London";
        d[@"usa"] = @"America/New_York";
        named = d;
    });
    return named;
}

// Lowercase words -> time zone name, for "<word> time": the people
// of a country ("japanese time") and names for zones ("pacific time").
static NSDictionary<NSString *, NSString *> *AdjectiveZones(void)
{
    static NSDictionary *zones;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zones = @{
            @"german": @"Europe/Berlin",     @"british": @"Europe/London",   @"english": @"Europe/London",
            @"scottish": @"Europe/London",   @"welsh": @"Europe/London",     @"french": @"Europe/Paris",
            @"spanish": @"Europe/Madrid",    @"italian": @"Europe/Rome",     @"dutch": @"Europe/Amsterdam",
            @"belgian": @"Europe/Brussels",  @"swiss": @"Europe/Zurich",     @"austrian": @"Europe/Vienna",
            @"polish": @"Europe/Warsaw",     @"swedish": @"Europe/Stockholm", @"norwegian": @"Europe/Oslo",
            @"danish": @"Europe/Copenhagen", @"finnish": @"Europe/Helsinki", @"irish": @"Europe/Dublin",
            @"portuguese": @"Europe/Lisbon", @"greek": @"Europe/Athens",     @"czech": @"Europe/Prague",
            @"hungarian": @"Europe/Budapest", @"romanian": @"Europe/Bucharest", @"turkish": @"Europe/Istanbul",
            @"ukrainian": @"Europe/Kyiv",    @"israeli": @"Asia/Jerusalem",  @"emirati": @"Asia/Dubai",
            @"indian": @"Asia/Kolkata",      @"singaporean": @"Asia/Singapore", @"chinese": @"Asia/Shanghai",
            @"japanese": @"Asia/Tokyo",      @"korean": @"Asia/Seoul",       @"thai": @"Asia/Bangkok",
            @"indonesian": @"Asia/Jakarta",  @"australian": @"Australia/Sydney", @"egyptian": @"Africa/Cairo",
            @"nigerian": @"Africa/Lagos",    @"kenyan": @"Africa/Nairobi",   @"south african": @"Africa/Johannesburg",
            @"american": @"America/New_York", @"canadian": @"America/Toronto", @"mexican": @"America/Mexico_City",
            @"brazilian": @"America/Sao_Paulo", @"argentine": @"America/Argentina/Buenos_Aires",
            @"argentinian": @"America/Argentina/Buenos_Aires", @"chilean": @"America/Santiago",
            @"colombian": @"America/Bogota",
            @"central european": @"Europe/Berlin", @"eastern": @"America/New_York", @"central": @"America/Chicago",
            @"mountain": @"America/Denver",  @"pacific": @"America/Los_Angeles",
        };
    });
    return zones;
}

// Country codes and abbreviations that, in lowercase, are ordinary
// words: "arrive in time", "no time", "it's time", "pet time".
static NSSet<NSString *> *WordsThatAreNotZones(void)
{
    static NSSet *words;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        words = [NSSet setWithArray:@[@"in", @"no", @"it", @"at", @"be", @"us", @"id", @"co", @"ar", @"th", @"is", @"es",
                                      @"art", @"cat", @"cot", @"eat", @"pet", @"wet", @"wit", @"west", @"nst", @"ast"]];
    });
    return words;
}

static NSRegularExpression *Regex(NSString *pattern)
{
    return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
}

// The parts of text in quotes, which are taken as they are: nothing in
// them is read as a date, time, time zone or place. A quote mark after
// a space opens a part and one before a space closes it. One that opens
// a part while another is open means the other was a typo, as in
// `"lunch with Maria at "the lunch place"`, and one that closes none is
// text, as in 12". A part still open at the end runs to the end, as
// while it's being typed.
//
// parts: each part's text, without its quote marks.
// marks: where the quote marks are that open and close parts, or are
// typos, none of which is part of the event.
static void FindQuotedParts(NSString *text, NSMutableArray<NSValue *> *parts, NSMutableIndexSet *marks)
{
    NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\"“”„«»"];
    NSMutableCharacterSet *spaceBefore = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [spaceBefore addCharactersInString:@"([{"];
    NSMutableCharacterSet *spaceAfter = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [spaceAfter addCharactersInString:@".,;:!?)]}"];
    NSUInteger open = NSNotFound;
    for (NSUInteger i = 0; i < text.length; i++) {
        if (![quotes characterIsMember:[text characterAtIndex:i]]) continue;
        BOOL before = i == 0 || [spaceBefore characterIsMember:[text characterAtIndex:i - 1]];
        BOOL after = i + 1 == text.length || [spaceAfter characterIsMember:[text characterAtIndex:i + 1]];
        if (!before && !after) continue; // in a word
        if (open != NSNotFound && !(before && !after)) {
            [marks addIndex:open];
            [marks addIndex:i];
            [parts addObject:[NSValue valueWithRange:NSMakeRange(open + 1, i - open - 1)]];
            open = NSNotFound;
        }
        else if (before) {
            if (open != NSNotFound) [marks addIndex:open];
            open = i;
        }
    }
    if (open != NSNotFound) {
        [marks addIndex:open];
        [parts addObject:[NSValue valueWithRange:NSMakeRange(open + 1, text.length - open - 1)]];
    }
}

// Text folded for comparing: lowercase, without accents or dots.
static NSString *Folded(NSString *text)
{
    NSString *folded = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
    return [folded stringByReplacingOccurrencesOfString:@"." withString:@""];
}

// The month (1-12) a word names, in the user's language or English:
// the month's name, its short name, or the start of its name that is
// at least 3 letters long ("nov", "Novem", "mär"). 0 if none.
static NSInteger MonthForWord(NSString *word)
{
    word = Folded(word);
    if (word.length < 3) return 0;
    NSDateFormatter *formatter = [NSDateFormatter new];
    for (NSLocale *locale in @[NSLocale.currentLocale, [NSLocale localeWithLocaleIdentifier:@"en_US"]]) {
        formatter.locale = locale;
        NSInteger found = 0;
        BOOL ambiguous = NO;
        for (NSArray<NSString *> *names in @[formatter.monthSymbols, formatter.standaloneMonthSymbols,
                                             formatter.shortMonthSymbols, formatter.shortStandaloneMonthSymbols]) {
            for (NSUInteger i = 0; i < names.count && i < 12; i++) {
                NSString *name = Folded(names[i]);
                if ([name isEqualToString:word]) return i + 1;
                if ([name hasPrefix:word]) {
                    if (found && found != (NSInteger)i + 1) ambiguous = YES;
                    found = i + 1;
                }
            }
        }
        if (found && !ambiguous) return found;
    }
    return 0;
}

// The weekday (1 = Sunday) an English word names: "Tue", "Tues",
// "Tuesday" or "Tuesdays". 0 if none.
static NSInteger WeekdayForWord(NSString *word)
{
    NSArray<NSString *> *names = @[@"sunday", @"monday", @"tuesday", @"wednesday", @"thursday", @"friday", @"saturday"];
    NSString *w = word.lowercaseString;
    if ([w hasSuffix:@"days"]) w = [w substringToIndex:w.length - 1];
    if (w.length < 3) return 0;
    for (NSUInteger i = 0; i < names.count; i++) {
        if ([names[i] hasPrefix:w]) return i + 1;
    }
    return 0;
}

// The next day that is this weekday, a week on if it's today, as the
// detector has "Monday".
static NSDate *NextWeekday(NSInteger weekday, NSDate *now, NSCalendar *calendar)
{
    NSDate *today = [calendar startOfDayForDate:now];
    NSInteger days = (weekday - [calendar component:NSCalendarUnitWeekday fromDate:today] + 7) % 7;
    return [calendar dateByAddingUnit:NSCalendarUnitDay value:days ?: 7 toDate:today options:0];
}

@implementation NLEventParser

+ (NSDate *)dateFromTypedString:(NSString *)text near:(NSDate *)near calendar:(NSCalendar *)calendar
{
    NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length == 0) return nil;
    NSDate *today = [calendar startOfDayForDate:[NSDate new]];
    NSString *folded = Folded(s);
    if ([folded isEqualToString:@"today"]) return today;
    if ([folded isEqualToString:@"tomorrow"]) return [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
    if ([folded isEqualToString:@"yesterday"]) return [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];

    // A weekday in front, as in "Fri, 6 Nov".
    NSTextCheckingResult *weekday = [Regex(@"^(\\p{L}+)\\.?,\\s*") firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (weekday && MonthForWord([s substringWithRange:[weekday rangeAtIndex:1]]) == 0) {
        s = [s substringFromIndex:NSMaxRange(weekday.range)];
    }

    BOOL monthFirst = [[NSUserDefaults standardUserDefaults] integerForKey:kTypedDateOrder] == TypedDateOrderMonthDay;
    NSRange all = NSMakeRange(0, s.length);
    NSInteger (^number)(NSTextCheckingResult *, NSUInteger) = ^NSInteger(NSTextCheckingResult *m, NSUInteger group) {
        NSRange range = [m rangeAtIndex:group];
        return range.location == NSNotFound ? 0 : [s substringWithRange:range].integerValue;
    };
    NSInteger day = 0, month = 0, year = 0; // year 0: none typed
    NSTextCheckingResult *m;
    if ((m = [Regex(@"^(\\d{4})-(\\d{1,2})-(\\d{1,2})$") firstMatchInString:s options:0 range:all])) {
        // 2026-11-09
        year = number(m, 1); month = number(m, 2); day = number(m, 3);
    }
    else if ((m = [Regex(@"^(\\d{1,2})\\s*([./-])\\s*(\\d{1,2})(?:\\s*\\2\\s*(\\d{4}|\\d{2})?)?\\s*\\.?$") firstMatchInString:s options:0 range:all])) {
        // 9/11, 9.11., 9-11, 9/11/2027, 9.11.27
        NSInteger first = number(m, 1), second = number(m, 3);
        day   = monthFirst ? second : first;
        month = monthFirst ? first : second;
        year  = number(m, 4);
    }
    else if ((m = [Regex(@"^(\\d{1,2})(?:st|nd|rd|th)?\\.?\\s*(?:of\\s+)?(\\p{L}+)\\.?(?:,?\\s*(\\d{4}|\\d{2}))?$") firstMatchInString:s options:0 range:all])) {
        // 9 Nov, 9. November 2027, 9th of November
        day = number(m, 1);
        month = MonthForWord([s substringWithRange:[m rangeAtIndex:2]]);
        year = number(m, 3);
    }
    else if ((m = [Regex(@"^(\\p{L}+)\\.?\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?$") firstMatchInString:s options:0 range:all])) {
        // Nov 9, November 9th, 2027
        month = MonthForWord([s substringWithRange:[m rangeAtIndex:1]]);
        day = number(m, 2);
        year = number(m, 3);
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return nil;
    if (year > 0 && year < 100) year += 2000;

    // The day in a year, or nil if that year has no such day (30 Feb).
    NSDate* (^dayInYear)(NSInteger) = ^NSDate *(NSInteger y) {
        NSDateComponents *c = [NSDateComponents new];
        c.year = y; c.month = month; c.day = day;
        NSDate *date = [calendar dateFromComponents:c];
        NSDateComponents *check = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
        return (date && check.year == y && check.month == month && check.day == day) ? date : nil;
    };
    if (year > 0) return dayInYear(year);

    // No year: the one nearest to near, or the later one if it's
    // as near.
    NSDate *nearDay = [calendar startOfDayForDate:near ?: today];
    NSInteger nearYear = [calendar component:NSCalendarUnitYear fromDate:nearDay];
    NSDate *best = nil;
    for (NSInteger y = nearYear - 1; y <= nearYear + 1; y++) {
        NSDate *date = dayInYear(y);
        if (date && (!best || fabs([date timeIntervalSinceDate:nearDay]) <= fabs([best timeIntervalSinceDate:nearDay]))) {
            best = date;
        }
    }
    return best;
}

+ (NSTimeZone *)timeZoneForName:(NSString *)name
{
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length < 2) return nil;
    BOOL isUppercase = [name isEqualToString:name.uppercaseString] &&
                       ![name isEqualToString:name.lowercaseString];
    if (isUppercase) {
        // Country codes and abbreviations must be typed in capitals
        // so words like "is", "in" and "est" are left alone.
        NSString *zone = name.length == 2 ? CountryZones()[name] : nil;
        if (zone) return [NSTimeZone timeZoneWithName:zone];
        if (name.length >= 3 && name.length <= 5) {
            NSString *abbreviated = [NSTimeZone abbreviationDictionary][name];
            if (abbreviated) return [NSTimeZone timeZoneWithName:abbreviated];
        }
    }
    NSString *zone = NamedZones()[name.lowercaseString];
    return zone ? [NSTimeZone timeZoneWithName:zone] : nil;
}

// The word(s) before "time" name the zone, which makes them safe to
// read more loosely than a bare word: any case, and "german" too.
+ (NSTimeZone *)timeZoneNamedBeforeTimeWord:(NSString *)name
{
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSTimeZone *zone = [self timeZoneForName:name];
    if (zone) return zone;
    NSString *lowercase = name.lowercaseString;
    if ([WordsThatAreNotZones() containsObject:lowercase]) return nil;
    NSString *adjective = AdjectiveZones()[lowercase];
    if (adjective) return [NSTimeZone timeZoneWithName:adjective];
    return [self timeZoneForName:name.uppercaseString];
}

+ (NLEventDraft *)parse:(NSString *)text calendar:(NSCalendar *)calendar now:(NSDate *)now defaultDurationMinutes:(NSInteger)defaultDurationMinutes
{
    NLEventDraft *draft = [NLEventDraft new];
    draft.locationRange = NSMakeRange(NSNotFound, 0);
    NSMutableArray<NSValue *> *tokens = [NSMutableArray new];
    // Same length as text. Understood parts are blanked out with
    // U+0001 so later steps skip them and ranges stay valid. Quoted
    // parts and their quote marks are U+0002, so no step reads them.
    NSMutableString *mask = [text mutableCopy];
    NSMutableArray<NSValue *> *quotedParts = [NSMutableArray new];
    NSMutableIndexSet *quoteMarks = [NSMutableIndexSet new];
    FindQuotedParts(text, quotedParts, quoteMarks);
    void (^hide)(NSRange) = ^(NSRange range) {
        NSString *hidden = [@"" stringByPaddingToLength:range.length withString:@"\x02" startingAtIndex:0];
        [mask replaceCharactersInRange:range withString:hidden];
    };
    for (NSValue *part in quotedParts) hide(part.rangeValue);
    [quoteMarks enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { hide(NSMakeRange(i, 1)); }];
    void (^blank)(NSRange) = ^(NSRange range) {
        [tokens addObject:[NSValue valueWithRange:range]];
        NSString *blanks = [@"" stringByPaddingToLength:range.length withString:@"\x01" startingAtIndex:0];
        [mask replaceCharactersInRange:range withString:blanks];
    };
    // Blanks out an understood part, but not the quoted parts in it.
    void (^claim)(NSRange) = ^(NSRange range) {
        NSUInteger i = range.location, end = NSMaxRange(range);
        while (i < end) {
            while (i < end && [mask characterAtIndex:i] == 0x02) i++;
            NSUInteger start = i;
            while (i < end && [mask characterAtIndex:i] != 0x02) i++;
            if (i > start) blank(NSMakeRange(start, i - start));
        }
    };
    NSRange whole = NSMakeRange(0, text.length);

    // ---- Time zone: "<name> time" (NY time, Tokyo time, japanese time)
    NSTimeZone *timeZone = nil;
    for (NSTextCheckingResult *m in [Regex(@"\\btime\\b") matchesInString:mask options:0 range:whole]) {
        // Try the 3, 2 and 1 words before "time".
        NSString *before = [mask substringToIndex:m.range.location];
        NSArray<NSTextCheckingResult *> *words = [Regex(@"[\\p{L}.]+") matchesInString:before options:0 range:NSMakeRange(0, before.length)];
        for (NSInteger n = MIN(3, (NSInteger)words.count); n >= 1 && !timeZone; n--) {
            NSUInteger start = words[words.count - n].range.location;
            NSString *gap = [before substringFromIndex:NSMaxRange(words.lastObject.range)];
            if ([gap stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) break;
            // Letters at the end of a number aren't a word: "4th time".
            if (start > 0 && [NSCharacterSet.decimalDigitCharacterSet characterIsMember:[before characterAtIndex:start - 1]]) continue;
            NSString *name = [before substringFromIndex:start];
            timeZone = [self timeZoneNamedBeforeTimeWord:name];
            if (timeZone) claim(NSMakeRange(start, NSMaxRange(m.range) - start));
        }
        if (timeZone) break;
    }
    // ---- Time zone: a bare abbreviation in capitals (CET, PST, UTC)
    if (!timeZone) {
        NSRegularExpression *abbr = [NSRegularExpression regularExpressionWithPattern:@"\\b[A-Z]{3,5}\\b" options:0 error:NULL];
        for (NSTextCheckingResult *m in [abbr matchesInString:mask options:0 range:whole]) {
            NSString *name = [mask substringWithRange:m.range];
            if ([NSTimeZone abbreviationDictionary][name]) {
                timeZone = [self timeZoneForName:name];
                if (timeZone) { claim(m.range); break; }
            }
        }
    }
    draft.timeZone = timeZone;

    // ---- Duration: "for 2 hours", "for 45 min"
    NSTimeInterval duration = 0;
    NSTextCheckingResult *dm = [Regex(@"\\bfor\\s+(\\d+(?:[.,]\\d+)?)\\s*(hours?|hrs?|h|minutes?|mins?|m)\\b") firstMatchInString:mask options:0 range:whole];
    if (dm) {
        NSString *number = [[mask substringWithRange:[dm rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSString *unit = [mask substringWithRange:[dm rangeAtIndex:2]].lowercaseString;
        duration = number.doubleValue * ([unit hasPrefix:@"h"] ? 3600 : 60);
        claim(dm.range);
    }

    // ---- Repeat: "every day", "every week", "every other week",
    // "every 2 weeks", "every month", "every year", and "every Tuesday",
    // which is also the day it starts.
    NSDate *dayDate = nil, *timeDate = nil;
    BOOL hasExplicitYear = NO;
    for (NSTextCheckingResult *m in [Regex(@"\\bevery\\s*(?:(other|second|2nd|2|two)\\s+)?(\\p{L}+)\\b") matchesInString:mask options:0 range:whole]) {
        BOOL everyOther = [m rangeAtIndex:1].location != NSNotFound;
        NSString *unit = [mask substringWithRange:[m rangeAtIndex:2]].lowercaseString;
        NSInteger weekday = WeekdayForWord(unit);
        NLEventRepeat repeat;
        if (weekday || [unit isEqualToString:@"week"] || [unit isEqualToString:@"weeks"]) {
            repeat = everyOther ? NLEventRepeatEveryTwoWeeks : NLEventRepeatWeekly;
        }
        // The Repeat menu has no other "every other".
        else if (everyOther) continue;
        else if ([unit isEqualToString:@"day"]) repeat = NLEventRepeatDaily;
        else if ([unit isEqualToString:@"month"]) repeat = NLEventRepeatMonthly;
        else if ([unit isEqualToString:@"year"]) repeat = NLEventRepeatYearly;
        else continue;
        draft.repeat = repeat;
        if (weekday) dayDate = NextWeekday(weekday, now, calendar);
        claim(m.range);
        break;
    }

    // ---- Dates as numbers: "6/11", "6.11.", "6/11/2027", and ranges
    // of them: "20.11. to 22.11.". Read day first or month first as set
    // in Settings, not as the Mac's region has it, as the detector below
    // would. A dot needs a year or a dot after it, since "9.30" is a
    // time. Dashes aren't dates here, since "9-11" is a time too.
    NSInteger rangeDays = 0; // days after the first, for a range of days
    NSRegularExpression *numericDate = Regex(@"(?<![\\d./:])(\\d{1,2})([/.])(\\d{1,2})(?:\\2(\\d{4}|\\d{2}))?(\\.?)(?![\\d/:])");
    BOOL (^isNumericDate)(NSTextCheckingResult *) = ^BOOL(NSTextCheckingResult *m) {
        BOOL hasYear = [m rangeAtIndex:4].location != NSNotFound;
        BOOL isDot = [[mask substringWithRange:[m rangeAtIndex:2]] isEqualToString:@"."];
        if (isDot && !hasYear && [m rangeAtIndex:5].length == 0) return NO;
        NSRange before = NSMakeRange(0, m.range.location);
        return !(isDot && [Regex(@"\\bat\\s+$") firstMatchInString:mask options:0 range:before]);
    };
    for (NSTextCheckingResult *m in [numericDate matchesInString:mask options:0 range:whole]) {
        if (!isNumericDate(m)) continue;
        NSDate *date = [self dateFromTypedString:[mask substringWithRange:m.range] near:now calendar:calendar];
        if (!date) continue;
        dayDate = date;
        hasExplicitYear = [m rangeAtIndex:4].location != NSNotFound;
        // Take the "on" in front of it too.
        NSRange range = m.range;
        NSTextCheckingResult *prep = [Regex(@"\\bon\\s+$") firstMatchInString:mask options:0 range:NSMakeRange(0, m.range.location)];
        if (prep) range = NSMakeRange(prep.range.location, NSMaxRange(range) - prep.range.location);
        // And the last day, if it's a range.
        NSRange afterDate = NSMakeRange(NSMaxRange(m.range), mask.length - NSMaxRange(m.range));
        NSTextCheckingResult *to = [Regex(@"\\s*(?:-|–|—|to|till|until)\\s*") firstMatchInString:mask options:NSMatchingAnchored range:afterDate];
        NSTextCheckingResult *m2 = to ? [numericDate firstMatchInString:mask options:NSMatchingAnchored range:NSMakeRange(NSMaxRange(to.range), mask.length - NSMaxRange(to.range))] : nil;
        NSDate *lastDay = (m2 && isNumericDate(m2)) ? [self dateFromTypedString:[mask substringWithRange:m2.range] near:date calendar:calendar] : nil;
        if (lastDay && [lastDay compare:date] == NSOrderedDescending) {
            rangeDays = [calendar components:NSCalendarUnitDay fromDate:date toDate:lastDay options:0].day;
            range.length = NSMaxRange(m2.range) - range.location;
        }
        claim(range);
        break;
    }

    // ---- A time from now: "in 2 hours", "in 30 min", "in half an hour"
    NSDate *relativeStart = nil;
    NSTextCheckingResult *im = [Regex(@"\\bin\\s+(\\d+(?:[.,]\\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|half\\s+an?)\\s*(hours?|hrs?|h|minutes?|mins?|m)\\b") firstMatchInString:mask options:0 range:whole];
    if (im) {
        NSString *amount = [mask substringWithRange:[im rangeAtIndex:1]].lowercaseString;
        NSDictionary<NSString *, NSNumber *> *numbers = @{@"a": @1, @"an": @1, @"one": @1, @"two": @2, @"three": @3, @"four": @4, @"five": @5,
                                                          @"six": @6, @"seven": @7, @"eight": @8, @"nine": @9, @"ten": @10};
        double n = numbers[amount] ? numbers[amount].doubleValue
                 : [amount hasPrefix:@"half"] ? 0.5
                 : [amount stringByReplacingOccurrencesOfString:@"," withString:@"."].doubleValue;
        BOOL hours = [[mask substringWithRange:[im rangeAtIndex:2]].lowercaseString hasPrefix:@"h"];
        NSTimeInterval at = now.timeIntervalSinceReferenceDate + n * (hours ? 3600 : 60);
        relativeStart = [NSDate dateWithTimeIntervalSinceReferenceDate:floor(at / 60) * 60];
        claim(im.range);
    }

    // ---- Times without am/pm: "at 9.30", "at 5", "9:15", "12.30-13.30",
    // "from 9 to 5". The detector misses some of these, and reads others
    // as the next such time, so 9:30 typed in the afternoon is 21:30.
    // Here, a time is 24-hour if it's 12 or more or starts with 0, and
    // else between 7am and 7pm: 9 is 9am and 5 is 5pm. With dinner,
    // drinks and the like, 7 to 11 are pm, and with breakfast or in the
    // morning, 1 to 6 are am. A time needs minutes, or "at", "from" or
    // "@" in front: "Standup 9" has none. Times with am/pm are left to
    // the detector, which reads those well.
    BOOL evening = [Regex(@"\\b(?:dinner|supper|drinks|party|tonight|evening|night|pub|concert|gig|theat(?:re|er)|movie|cinema)\\b") firstMatchInString:text options:0 range:whole] != nil;
    BOOL morning = [Regex(@"\\b(?:breakfast|morning)\\b") firstMatchInString:text options:0 range:whole] != nil;
    NSInteger (^hourFor)(NSString *) = ^NSInteger(NSString *digits) {
        NSInteger h = digits.integerValue;
        if (h >= 12 || h == 0 || [digits hasPrefix:@"0"]) return h;
        if (h <= 6) return morning ? h : h + 12;
        return evening ? h + 12 : h;
    };
    NSRegularExpression *clock = Regex(@"(?:\\b(?:at|from)\\s+|@\\s*)?(?<![\\w.:/£$€¥#\\-–])(\\d{1,2})(?:[:.](\\d{2}))?"
                                       @"(?:\\s*(?:-|–|—|to|till|until)\\s*(\\d{1,2})(?:[:.](\\d{2}))?)?"
                                       @"(?![\\w:/%]|\\.\\d|\\s*(?:am\\b|pm\\b|a\\.m\\.|p\\.m\\.|(?:-|–|—|to\\b|till\\b|until\\b)\\s*\\d))");
    // Words after a number that isn't a time: "at 5 people".
    NSSet<NSString *> *units = [NSSet setWithArray:@[@"min", @"mins", @"minute", @"minutes", @"h", @"hr", @"hrs", @"hour", @"hours",
                                                     @"day", @"days", @"week", @"weeks", @"month", @"months", @"year", @"years",
                                                     @"people", @"person", @"persons", @"pax", @"guests", @"x"]];
    NSTimeInterval clockDuration = 0;
    for (NSTextCheckingResult *m in [clock matchesInString:mask options:0 range:whole]) {
        NSString *(^group)(NSUInteger) = ^NSString *(NSUInteger i) {
            NSRange r = [m rangeAtIndex:i];
            return r.location == NSNotFound ? nil : [mask substringWithRange:r];
        };
        BOOL prefixed = m.range.location != [m rangeAtIndex:1].location;
        if (!prefixed && !group(2) && !group(4)) continue;
        if (group(1).integerValue > 23 || group(2).integerValue > 59 || group(3).integerValue > 24 || group(4).integerValue > 59) continue;
        // Days of a month, as in "3-5 Dec" and "Dec 3-5", or a number
        // of things.
        NSString *after = [mask substringFromIndex:NSMaxRange(m.range)];
        NSTextCheckingResult *nextMatch = [Regex(@"^\\s*(\\p{L}+)") firstMatchInString:after options:0 range:NSMakeRange(0, after.length)];
        NSString *next = nextMatch ? [after substringWithRange:[nextMatch rangeAtIndex:1]] : nil;
        NSString *before = [mask substringToIndex:[m rangeAtIndex:1].location];
        NSTextCheckingResult *previousMatch = [Regex(@"(\\p{L}+)\\.?\\s*$") firstMatchInString:before options:0 range:NSMakeRange(0, before.length)];
        NSString *previous = previousMatch ? [before substringWithRange:[previousMatch rangeAtIndex:1]] : nil;
        if ((next && (MonthForWord(next) || [units containsObject:next.lowercaseString])) || (previous && MonthForWord(previous))) continue;
        // A whole hour before a name that isn't a day is part of a
        // place: "at 10 Downing Street".
        BOOL nameNext = next && [NSCharacterSet.uppercaseLetterCharacterSet characterIsMember:[next characterAtIndex:0]];
        if (nameNext && !group(2) && !WeekdayForWord(next) &&
            ![@[@"today", @"tomorrow", @"tonight"] containsObject:next.lowercaseString]) continue;

        NSInteger start = hourFor(group(1)) * 60 + group(2).integerValue;
        if (group(3)) {
            // The end is the first of h and h + 12 after the start.
            NSInteger h = group(3).integerValue, end = h * 60 + group(4).integerValue;
            if (h < 12 && ![group(3) hasPrefix:@"0"] && end <= start) end += 12 * 60;
            if (end <= start) end += 24 * 60;
            clockDuration = (end - start) * 60;
        }
        timeDate = [calendar dateBySettingHour:start / 60 minute:start % 60 second:0 ofDate:now options:0];
        claim(m.range);
        break;
    }
    if (duration == 0) duration = clockDuration;

    // ---- Dates and times
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:NULL];
    // The detector must not see the blanks or quoted parts as text, nor
    // meals: it reads "Wed noon lunch" as a time, and "noon dinner" as
    // 6pm, leaving "lunch" out of "lunch with Maria".
    NSString *detectable = [mask stringByReplacingOccurrencesOfString:@"\x01" withString:@" "];
    detectable = [detectable stringByReplacingOccurrencesOfString:@"\x02" withString:@" "];
    NSMutableString *withoutMeals = [detectable mutableCopy];
    for (NSTextCheckingResult *m in [Regex(@"\\b(?:breakfast|brunch|lunch|dinner|supper)\\b") matchesInString:detectable options:0 range:whole]) {
        [withoutMeals replaceCharactersInRange:m.range withString:[@"" stringByPaddingToLength:m.range.length withString:@" " startingAtIndex:0]];
    }
    detectable = withoutMeals;
    NSRegularExpression *timeRegex = Regex(@"\\b\\d{1,2}(?:[:.]\\d{2})?\\s*(?:am|pm|a\\.m\\.|p\\.m\\.)|\\b\\d{1,2}:\\d{2}\\b|\\b(?:noon|midday|midnight|morning|afternoon|evening|tonight)\\b");
    NSTimeInterval detectedDuration = 0;
    for (NSTextCheckingResult *m in [detector matchesInString:detectable options:0 range:whole]) {
        if (!m.date) continue;
        NSString *matched = [detectable substringWithRange:m.range];
        NSRange matchedRange = NSMakeRange(0, matched.length);
        BOOL hasTime = [timeRegex firstMatchInString:matched options:0 range:matchedRange] != nil;
        NSString *rest = [timeRegex stringByReplacingMatchesInString:matched options:0 range:matchedRange withTemplate:@""];
        rest = [Regex(@"\\b(?:at|on|from|to|until|till)\\b|[\\s,.\\-–]") stringByReplacingMatchesInString:rest options:0 range:NSMakeRange(0, rest.length) withTemplate:@""];
        BOOL hasDay = rest.length > 0;
        if (!hasTime && !hasDay) continue;
        if (hasDay && !dayDate) {
            dayDate = m.date;
            hasExplicitYear = [Regex(@"\\b\\d{4}\\b") firstMatchInString:matched options:0 range:matchedRange] != nil;
            // A range of days, as in "20-24 Dec": it gives the length.
            if (!hasTime && m.duration >= 86400) rangeDays = lround(m.duration / 86400);
        }
        if (hasTime && !timeDate) {
            timeDate = m.date;
            detectedDuration = m.duration;
        }
        NSRange range = m.range;
        // "Movie night Friday": the detector takes "night" with the day.
        NSTextCheckingResult *night = [Regex(@"^night\\s+") firstMatchInString:matched options:0 range:matchedRange];
        if (night) {
            range.location += night.range.length;
            range.length -= night.range.length;
        }
        // Take the "on"/"at"/"from" in front of it too.
        NSTextCheckingResult *prep = [Regex(@"\\b(?:on|at|from)\\s+$") firstMatchInString:detectable options:0 range:NSMakeRange(0, range.location)];
        if (prep) range = NSMakeRange(prep.range.location, NSMaxRange(range) - prep.range.location);
        claim(range);
    }
    if (duration == 0) duration = detectedDuration;

    // ---- A short weekday on its own, which the detector misses ("Wed",
    // but not "Wed 3pm" or "Thu"): the next one, as the detector has it.
    if (!dayDate) {
        // In lowercase, these are words, and in capitals, like SAT, a
        // weekday is unlikely.
        NSSet<NSString *> *words = [NSSet setWithArray:@[@"wed", @"sat", @"sun"]];
        NSRegularExpression *weekdayRegex = Regex(@"\\b(?:on\\s+)?(mon|tues?|wed|thu(?:rs?)?|fri|sat|sun)\\b\\.?");
        for (NSTextCheckingResult *m in [weekdayRegex matchesInString:mask options:0 range:whole]) {
            NSString *word = [mask substringWithRange:[m rangeAtIndex:1]];
            if ([words containsObject:word] || [word isEqualToString:word.uppercaseString]) continue;
            dayDate = NextWeekday(WeekdayForWord(word), now, calendar);
            hasExplicitYear = NO;
            claim(m.range);
            break;
        }
    }

    // ---- A day of the month: "on the 21st", the next one.
    NSTextCheckingResult *dom = dayDate ? nil : [Regex(@"\\b(?:on\\s+)?the\\s+(\\d{1,2})(?:st|nd|rd|th)\\b") firstMatchInString:mask options:0 range:whole];
    if (dom) {
        NSInteger day = [mask substringWithRange:[dom rangeAtIndex:1]].integerValue;
        NSDate *today = [calendar startOfDayForDate:now];
        NSDateComponents *c = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:today];
        // This month's, or the next month's that has the day.
        for (NSInteger i = 0; i < 12 && day >= 1 && day <= 31 && !dayDate; i++, c.month++) {
            c.day = day;
            NSDate *date = [calendar dateFromComponents:c];
            if ([calendar component:NSCalendarUnitDay fromDate:date] == day && [date compare:today] != NSOrderedAscending) {
                dayDate = date;
            }
        }
        if (dayDate) claim(dom.range);
    }

    // ---- Location: "at <place>" or "@ <place>": a quoted part right
    // after it, or else up to the next understood or quoted part or the
    // end.
    NSMutableDictionary<NSNumber *, NSValue *> *partAt = [NSMutableDictionary new];
    for (NSValue *part in quotedParts) partAt[@(part.rangeValue.location)] = part;
    NSRegularExpression *locRegex = Regex(@"(?:^|\\s)(?:at|@)\\s+(?:([^\\x01\\x02]*[^\\x01\\x02\\s,;])|\\x02)");
    for (NSTextCheckingResult *lm in [locRegex matchesInString:mask options:0 range:whole]) {
        NSRange nameRange = [lm rangeAtIndex:1];
        NSRange range = lm.range;
        if (nameRange.location == NSNotFound) {
            // The quote mark that opens a part, and the part.
            NSValue *part = partAt[@(NSMaxRange(lm.range))];
            if (!part) continue;
            nameRange = part.rangeValue;
            NSUInteger end = NSMaxRange(nameRange) + ([quoteMarks containsIndex:NSMaxRange(nameRange)] ? 1 : 0);
            range = NSMakeRange(range.location, end - range.location);
        }
        NSString *location = [[text substringWithRange:nameRange] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (location.length == 0) continue;
        draft.location = location;
        draft.locationRange = nameRange;
        // Don't claim the space in front of "at".
        while (range.length && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:range.location]]) {
            range.location++; range.length--;
        }
        blank(range);
        break;
    }

    // ---- Title: what is left, with the quoted parts as they are.
    // While it's tidied up, each quoted part is one private-use
    // character, so nothing in it changes.
    NSMutableString *left = [NSMutableString new];
    NSMutableArray<NSString *> *quotedTexts = [NSMutableArray new];
    for (NSUInteger i = 0; i < mask.length; ) {
        unichar ch = [mask characterAtIndex:i];
        NSUInteger next = i + 1;
        if (ch == 0x01 || [quoteMarks containsIndex:i]) {
            [left appendString:@" "];
        }
        else if (ch == 0x02) {
            NSValue *part = partAt[@(i)];
            if (part) {
                NSString *quoted = [[text substringWithRange:part.rangeValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (quoted.length) {
                    [left appendFormat:@"%C", (unichar)(0xE000 + quotedTexts.count)];
                    [quotedTexts addObject:quoted];
                }
                next = MAX(next, NSMaxRange(part.rangeValue));
            }
        }
        else {
            [left appendString:[mask substringWithRange:NSMakeRange(i, 1)]];
        }
        i = next;
    }
    NSString *title = [Regex(@"\\s+") stringByReplacingMatchesInString:left options:0 range:NSMakeRange(0, left.length) withTemplate:@" "];
    title = [Regex(@"\\s+([,;])") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    title = [Regex(@"([,;])(?:\\s*[,;])+") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    // A full stop left on its own, as after "at 9.30.".
    title = [Regex(@"\\s+\\.(?=\\s|$)") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    NSMutableCharacterSet *trim = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [trim addCharactersInString:@",;-–—"];
    title = [title stringByTrimmingCharactersInSet:trim];
    // A preposition left dangling at the end, e.g. "Lunch on".
    title = [Regex(@"\\s+(?:on|at|from|in)$") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    title = [title stringByTrimmingCharactersInSet:trim];
    for (NSUInteger k = 0; k < quotedTexts.count; k++) {
        title = [title stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%C", (unichar)(0xE000 + k)] withString:quotedTexts[k]];
    }
    draft.title = title;
    draft.tokenRanges = tokens;

    // ---- Start and end
    if (!dayDate && !timeDate) {
        // Only a time from now, if that.
        if (relativeStart) {
            draft.startDate = relativeStart;
            draft.endDate = [relativeStart dateByAddingTimeInterval:duration > 0 ? duration : MAX(defaultDurationMinutes, 1) * 60];
        }
        return draft;
    }

    NSCalendarUnit ymd = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDateComponents *c = [calendar components:ymd fromDate:dayDate ?: timeDate];
    if (dayDate && !hasExplicitYear) {
        // "12 Nov" means the next 12 Nov, not one that has passed.
        NSDate *day = [calendar dateFromComponents:c];
        NSDate *today = [calendar startOfDayForDate:now];
        if ([day compare:today] == NSOrderedAscending &&
            [today timeIntervalSinceDate:day] > 2 * 86400) {
            NSDate *nextYear = [calendar dateByAddingUnit:NSCalendarUnitYear value:1 toDate:day options:0];
            NSDate *aYearAgo = [calendar dateByAddingUnit:NSCalendarUnitYear value:-1 toDate:today options:0];
            // Only if the detector guessed this year, not for
            // phrases like "last Friday".
            if ([day compare:aYearAgo] == NSOrderedDescending &&
                [Regex(@"\\b(?:last|yesterday|ago)\\b") firstMatchInString:text options:0 range:whole] == nil) {
                c = [calendar components:ymd fromDate:nextYear];
            }
        }
    }

    if (!timeDate) {
        draft.allDay = YES;
        draft.startDate = [calendar dateFromComponents:c];
        NSInteger extraDays = MAX(rangeDays, duration >= 86400 ? (NSInteger)(duration / 86400) : 0);
        draft.endDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:extraDays toDate:draft.startDate options:0];
        return draft;
    }

    NSDateComponents *t = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:timeDate];
    c.hour = t.hour;
    c.minute = t.minute;
    // The wall-clock time is in the named time zone, if any.
    NSCalendar *zoned = [calendar copy];
    if (timeZone) zoned.timeZone = timeZone;
    NSDate *start = [zoned dateFromComponents:c];
    if (!dayDate && [start compare:now] == NSOrderedAscending) {
        // Just a time, and it has passed today: tomorrow.
        start = [zoned dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
    }
    draft.startDate = start;
    if (duration <= 0) duration = MAX(defaultDurationMinutes, 1) * 60;
    draft.endDate = [start dateByAddingTimeInterval:duration];
    return draft;
}

@end
