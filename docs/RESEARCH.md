# User research: what people want fixed in cutting-machine design software

Collected 2026-10-18. The original target was r/cricut, but Reddit blocks the
crawler used to gather this, so the feedback below comes from public review
sites, blogs and forums instead. Treat it as a sample, not a survey.

Sources:

- [Dinosaur Mama: Design Space Update 2026](https://dinosaurmama.com/post/cricut-design-space-update-2026/) (with comments)
- [Dinosaur Mama: June 2026 Update Explained](https://dinosaurmama.com/post/cricut-june-2026-update/) (with comments)
- [JustUseApp: problems](https://justuseapp.com/en/app/749471884/cricut-design-space/problems)
- [JustUseApp: reviews](https://justuseapp.com/en/app/749471884/cricut-design-space/reviews)
- [Craft Industry Alliance: Can Cricut recover…](https://craftindustryalliance.org/can-cricut-recover-from-its-stumble-over-design-space/)
- [Cuttabl: alternatives](https://cuttabl.co/blog/cricut-design-space-alternatives)
- [Atomm: alternatives](https://www.atomm.com/blog/2671-cricut-alternatives)
- [iMore: upload limit reversal](https://imore.com/cricut-reverses-20-image-upload-limit)
- [Trustpilot](https://au.trustpilot.com/review/cricut.com)

## Themes, ranked by how often they came up

1. **Lost work.** Crashes, forced updates, auto-logout and "saved" projects that
   were never saved. One user lost three days of work.
2. **Cloud lock-in.** Needs internet and an account. Projects can't be exported
   to other programs. Deleting the app wipes local saves.
3. **Weak editing tools.** No node editing, eraser, crop or freehand drawing.
   Snapping can't be turned off. Slice and offset are buggy. Contour isn't
   available on imported images.
4. **Text.** Poor default kerning. Welded script text degrades. Curve works only
   on single-line text. Fonts randomly vanish and don't move between devices.
5. **Mat workflow.** You can't freely move items on the mat, choose which mat to
   cut first, toggle auto-packing, or set cut depth per layer.
6. **Print then Cut.** The printable area is too small for a letter-size sheet,
   cuts drift from the print, and it isn't available on every platform.
7. **UI churn.** Redesigns hide tools behind panels and break muscle memory.
   Users ask for keyboard shortcuts and a blank canvas on launch.
8. **Paywalls and upsells.** Core tools (Warp, at times Sticker) sit behind a
   subscription, premium suggestions push past your own uploads, and there was
   a 2021 attempt to cap free uploads at 20 a month.
9. **Project organization.** Search doesn't find your own projects by name, and
   there are no folders or favorites.
10. **Slowness.** Slow undo, lag with many layers, slow font loading.

## What competitors are praised for

- **Silhouette Studio:** works offline, stronger drawing and node editing, no
  subscription prompts.
- **Inkscape:** real vector editing, tracing, clean SVG.
- **ScanNCut:** scan-to-cut and no subscription.

## Round 2 (2026-10-18): app stores, review sites and forums

Reddit stayed off limits. An unofficial Reddit mirror turned up in search, but
it was skipped on purpose because using it would get around Reddit's block.

New sources:

- [App Store reviews](https://apps.apple.com/us/app/cricut-design-space/id749471884?see-all=reviews) (about 10 loaded)
- [ProductReview.com.au](https://www.productreview.com.au/listings/cricut-design-space)
- [PissedConsumer](https://cricut.pissedconsumer.com/review.html) (mostly billing; software items noted)
- [Trustpilot, page 2](https://www.trustpilot.com/review/cricut.com?page=2)
- Apple Community: [iPad lag](https://discussions.apple.com/thread/255542988), [Mac won't launch](https://discussions.apple.com/thread/253616358), [malware warning](https://discussions.apple.com/thread/254214474)
- [DIS Boards](https://www.disboards.com/threads/cricut-design-space.3794901/), [Rocketry Forum](https://www.rocketryforum.com/threads/cricut-drops-a-subscription-bomb-on-its-users.165257/), [Designer Trapped](https://designertrapped.com/silhouette-vs-cricut-review/)
- Cricut's own help pages on [offline mode](https://help.cricut.com/hc/articles/360033894014) and [supported platforms](https://help.cricut.com/hc/en-us/articles/360009503353-Design-Space-FAQ)

Could not be read: scrapbook.com (403), a Lemmy thread (500), and the Cricut
offline-mode article when fetched directly (403; its search summary is used).

### New themes, and how Open Design Space compares

| Theme from users | Open Design Space today |
| --- | --- |
| Signed out in the background on iOS, losing the canvas | No accounts; autosave every second or two |
| Uploaded images can't be edited once on the canvas | Crop and trace work at any time; **no background remover yet** |
| Saw another user's uploads and photos | Everything stays on the device |
| Forced updates, no way to stay on or roll back a version | Every release stays downloadable; nothing updates itself |
| Updates drop devices people own (iPhone 12, Windows 7); no Linux or Chromebook | Windows, macOS, Linux, Android, iOS, web. Windows 7 isn't supported by Flutter |
| Offline mode can't upload or use templates; none on Android | Fully offline everywhere, imports included |
| Cut width capped at 11.5" on a 12" mat | Edge margin is a setting |
| No batch upload | Import accepts many files at once |
| Icons and text too small, no way to enlarge them | View > Interface size, 90% to 150%, saved on the device |
| Nudge steps too coarse for lining up text | Arrow keys move 1 mm or 1/16 in (Shift: 10×); Alt + arrow moves 0.1 mm or 1/100 in |
| Paywall on your own uploads; constant upsells; two subscriptions | Free, no store, no upsells |
| Login fails on managed corporate networks | No login, no network |
| Outages for days | Doesn't depend on a server |
| Print dialog hidden behind the app | Uses the system print dialog; **not yet tested on Windows** |
| Very slow on iPad Pro | `test/perf_test.dart` times 300 shapes plus curved text; outlines and bounds are now cached, so dragging is about twice as fast. **Not yet measured on a real iPad** |
| No text on a curved path | Curved text works; **text along any path doesn't** |
| Not precise enough for exact parts | Millimetre or inch fields to 0.01; geometry runs at 0.05 mm |
| Has to use the maker's software to cut | **Still true for Cricut machines**: exports SVG/DXF/HPGL only |
| Machine reconnects for every cut; mat doesn't advance; blade pressure resets | Not applicable: no machine control |
| Mac app blank or stuck on an update loop | Not seen in local testing; unsigned builds show a one-time prompt |

Also noted: one Trustpilot reviewer said Cricut has been hostile to
open-source alternatives. That supports keeping this project clean-room and
leaving machine drivers out of it.
