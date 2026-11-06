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
    // U+0001 so later steps skip them and ranges stay valid.
    NSMutableString *mask = [text mutableCopy];
    void (^claim)(NSRange) = ^(NSRange range) {
        [tokens addObject:[NSValue valueWithRange:range]];
        NSString *blank = [@"" stringByPaddingToLength:range.length withString:@"\x01" startingAtIndex:0];
        [mask replaceCharactersInRange:range withString:blank];
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

    // ---- Dates as numbers: "6/11", "6.11.", "6/11/2027". Read day
    // first or month first as set in Settings, not as the Mac's region
    // has it, as the detector below would. A dot needs a year or a dot
    // after it, since "9.30" is a time. Dashes aren't dates here, since
    // "9-11" is a time too.
    NSDate *dayDate = nil, *timeDate = nil;
    BOOL hasExplicitYear = NO;
    NSRegularExpression *numericDate = Regex(@"(?<![\\d./:])(\\d{1,2})([/.])(\\d{1,2})(?:\\2(\\d{4}|\\d{2}))?(\\.?)(?![\\d/:])");
    for (NSTextCheckingResult *m in [numericDate matchesInString:mask options:0 range:whole]) {
        BOOL hasYear = [m rangeAtIndex:4].location != NSNotFound;
        BOOL isDot = [[mask substringWithRange:[m rangeAtIndex:2]] isEqualToString:@"."];
        if (isDot && !hasYear && [m rangeAtIndex:5].length == 0) continue;
        NSRange before = NSMakeRange(0, m.range.location);
        if (isDot && [Regex(@"\\bat\\s+$") firstMatchInString:mask options:0 range:before]) continue;
        NSDate *date = [self dateFromTypedString:[mask substringWithRange:m.range] near:now calendar:calendar];
        if (!date) continue;
        dayDate = date;
        hasExplicitYear = hasYear;
        // Take the "on" in front of it too.
        NSRange range = m.range;
        NSTextCheckingResult *prep = [Regex(@"\\bon\\s+$") firstMatchInString:mask options:0 range:before];
        if (prep) range = NSMakeRange(prep.range.location, NSMaxRange(range) - prep.range.location);
        claim(range);
        break;
    }

    // ---- Dates and times
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:NULL];
    // The detector must not see the blanks as text.
    NSString *detectable = [mask stringByReplacingOccurrencesOfString:@"\x01" withString:@" "];
    NSRegularExpression *timeRegex = Regex(@"\\b\\d{1,2}(?:[:.]\\d{2})?\\s*(?:am|pm|a\\.m\\.|p\\.m\\.)|\\b\\d{1,2}:\\d{2}\\b|\\b(?:noon|midnight|morning|afternoon|evening|tonight)\\b");
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
        }
        if (hasTime && !timeDate) {
            timeDate = m.date;
            detectedDuration = m.duration;
        }
        // Take the "on"/"at"/"from" in front of it too.
        NSRange range = m.range;
        NSTextCheckingResult *prep = [Regex(@"\\b(?:on|at|from)\\s+$") firstMatchInString:detectable options:0 range:NSMakeRange(0, range.location)];
        if (prep) range = NSMakeRange(prep.range.location, NSMaxRange(range) - prep.range.location);
        claim(range);
    }
    if (duration == 0) duration = detectedDuration;

    // ---- Location: "at <place>" or "@ <place>", up to the next
    // understood part or the end.
    NSRegularExpression *locRegex = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)(?:at|@)\\s+([^\\x01]*[^\\x01\\s,;])" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *lm = [locRegex firstMatchInString:mask options:0 range:whole];
    if (lm) {
        NSRange nameRange = [lm rangeAtIndex:1];
        draft.location = [text substringWithRange:nameRange];
        draft.locationRange = nameRange;
        NSRange range = lm.range;
        // Don't claim the space in front of "at".
        while (range.length && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:range.location]]) {
            range.location++; range.length--;
        }
        claim(range);
    }

    // ---- Title: what is left
    NSString *title = [mask stringByReplacingOccurrencesOfString:@"\x01" withString:@" "];
    title = [Regex(@"\\s+") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@" "];
    title = [Regex(@"\\s+([,;])") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    title = [Regex(@"([,;])(?:\\s*[,;])+") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    NSMutableCharacterSet *trim = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [trim addCharactersInString:@",;-–—"];
    title = [title stringByTrimmingCharactersInSet:trim];
    // A preposition left dangling at the end, e.g. "Lunch on".
    title = [Regex(@"\\s+(?:on|at|from|in)$") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    draft.title = [title stringByTrimmingCharactersInSet:trim];
    draft.tokenRanges = tokens;

    // ---- Start and end
    if (!dayDate && !timeDate) return draft;

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
        NSInteger extraDays = duration >= 86400 ? (NSInteger)(duration / 86400) : 0;
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
