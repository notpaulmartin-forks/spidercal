# Spidercal

Forked from [Itsycal](https://github.com/sfsam/Itsycal)

- Type events in natural language, e.g. `Flight to London on 12 Nov at 4pm, DE time`. Understood dates, times, time zones and places are tinted, and a summary appears under the field. Press Return to save.
- Time zones in new events: `DE time`, `german time`, `germany time`, `CET`, `Tokyo time` and so on, plus a Time Zone row in the event form.
- Place suggestions while typing `at <place>` or filling in the location field. They use Apple's MapKit, so the place text you type is sent to Apple. Nothing is sent until you type a place.
- Search events by title, location or notes across the next 12 months. The New Event and Search fields swap places with a click, or with ⌘N and ⌘F.
- The full event form opens inline in the window instead of in a popover.
- The agenda is a scrolling list. Drag the window's bottom edge to make it taller or shorter, and double-click the edge to reset it.
- Slightly wider calendar, and spacing and type sizes that follow the size setting throughout.
- Removed the Sparkle auto-updater, which checked Itsycal's update feed. To update, rebuild from source.

**Install instructions**

Requires macOS 26 and Xcode 26 or newer. There are no prebuilt downloads, so build it yourself:

```bash
git clone https://github.com/notpaulmartin-forks/spidercal.git
cd spidercal
cp Local.xcconfig.example Local.xcconfig
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/Spidercal.app /Applications/Spidercal.app
open /Applications/Spidercal.app
```

Allow calendar access when asked, then tick the calendars you want under Settings → Events. Nothing shows until you do.

The Xcode project and source folder are still named Itsycal, to keep merging from upstream simple. The Help links still point to Itsycal's site.

# Original Itsycal README

I've learned a lot by looking at other people's code so
maybe someone can learn something from looking at mine.

= = = = = = = =

Itsycal is a tiny calendar for your Mac's menu bar.

If you want, it will display your calendar events as a
companion to the Mac Calendar app. You can also create
and delete (but not edit) events.

For more info, see: http://www.mowglii.com/itsycal

= = = = = = = =

This project uses a local xcconfig file for signing -
see CONTRIBUTING.md and Local.xcconfig.example

MIT Licensed - see License file
