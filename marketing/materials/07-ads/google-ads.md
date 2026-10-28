# Google Ads: keyword groups and responsive search ads

**Status:** drafts only. Nothing is set up or spent. Per strategy 03 section 5: only start after the first-run onboarding works end to end, analytics events exist, and the privacy policy and each store's data-safety answers are updated for any ad pixel. Start at the **$500/month tier at most**, and stop any campaign above **$60 per trial**.
**Rules:** no competitor names in keywords, ad copy, sitelinks or landing pages for ads. Church software CPCs and conversion rates are hypotheses (CPC $1 to $4, trial conversion 3 to 8 percent): measure your own.
**Prices:** none. Ads never state a price until pricing is decided. If you want a price in ads later, use `[PRICE]` in the template and fill it in then.
**Landing pages:** `../02-landing-and-waitlist/launch-landing-page.html` for the general ad group; build one page per persona later (kids ministry, signage, slides, small church).

## Campaign structure

| Campaign | Budget share | Match types | Goal |
|---|---|---|---|
| A. Kids ministry TV | 40% | Phrase and exact | Trial starts |
| B. Church signage | 30% | Phrase and exact | Trial starts |
| C. Church slides and lyrics | 15% | Phrase and exact | Trial starts |
| D. Hardware (Fire TV / Roku for church) | 15% | Phrase and exact | Trial starts |

Settings: United States, Canada (and UK, Australia once support hours are posted). English. Search network only (no Display, no Search Partners at first). Schedule Tuesday to Thursday and Sunday evening. Mobile bid adjustment neutral. Conversion events: `trial_started`, `tv_paired` (use `tv_paired` as the primary).

## Keyword groups

### A. Kids ministry TV
*Exact:* [kids church video player] [sunday school video player] [children's ministry video playlist] [kids ministry tv app] [nursery tv app for church]
*Phrase:* "kids church video player" "sunday school tv" "kids ministry countdown video" "children's church tv app" "church countdown timer for tv"
**Negatives:** free movies, cartoons, netflix, youtube kids, download, jobs, curriculum free, bible stories for kids, template, lesson plan, craft

### B. Church signage
*Exact:* [church digital signage] [church lobby tv software] [church announcement screen] [digital signage for churches] [church lobby screen]
*Phrase:* "church digital signage" "church lobby display" "church announcement slides" "church digital signage on fire stick" "portrait digital signage church"
**Negatives:** hardware only, led display, outdoor sign, billboard, jobs, template free, powerpoint template, church sign letters

### C. Church slides and lyrics
*Exact:* [church song lyrics on tv] [church slides without laptop] [display lyrics on tv church] [church presentation software for tv]
*Phrase:* "church lyrics display" "church slides on tv" "worship lyrics on a tv" "church slides on fire tv"
**Negatives:** song lyrics (alone), karaoke, free worship backgrounds, motion backgrounds download, ccli (alone), sheet music

### D. Hardware-led
*Exact:* [fire tv for church] [roku for church] [google tv for church]
*Phrase:* "fire stick for church" "roku church signage" "church tv app fire tv" "church tv app roku" "church tv app google tv"
**Negatives:** free movies, kodi, iptv, jailbreak, firestick tricks, apps for netflix, review, how to hack

**Do not bid on:** any competitor, curriculum or software brand names (see strategy 03 section 10). Do not add "alternative" terms that include a brand name.

## Responsive search ads

Google limits: up to 15 headlines (30 characters each) and 4 descriptions (90 characters each). Pin headline 1 where noted. The character counts below were checked.

### RSA 1: Kids ministry TV (Campaign A)
**Headlines (30 max):**
1. Kids Church Video on a TV (pin 1)
2. No Laptop in the Nursery
3. Church TV OS: Free Trial
4. Run Rooms From Your Phone
5. Fire TV, Google TV, Roku
6. Countdowns, Lyrics, Video
7. Schedule Sunday on Thursday
8. Volunteers Just Press Next
9. Keeps Playing Offline
10. Pair With a 6-Character Code
11. Kids Rooms, Lobby, Slides
12. Works on TVs You Own
13. Start Free, No Card to Look
14. One System, Every Screen
15. Sunday-Ready Screens

**Descriptions (90 max):**
1. Run each kids room from a Fire TV, Google TV or Roku. Set it Thursday, press Next Sunday.
2. Countdowns, lyrics and video that play themselves into the room. Keeps going offline.
3. Volunteers get an operator role: Next, Back, Blank. They can't edit anything. Try it free.
4. Pair a TV with a six-character code. Manage everything from the web or your phone.

**Final URL:** `https://churchtvos.com/?utm_source=google&utm_medium=paid&utm_campaign=launch2027&utm_content=kids_rsa1&utm_term={keyword}`
**Display path:** churchtvos.com / kids-rooms

### RSA 2: Church signage (Campaign B)
**Headlines:**
1. Church Digital Signage (pin 1)
2. Lobby Screens Run Themselves
3. Use the TVs You Already Own
4. Church TV OS: Free Trial
5. Fire TV, Google TV, Roku
6. Weekly Schedules, Easy Setup
7. Landscape or Portrait Screens
8. Black Screen When Idle
9. Signs, Pictures and Video
10. Set It Once, Run All Week
11. Kids on Sunday, Signs All Week
12. Manage From Your Phone
13. Start Free, No Card to Look
14. No Special Hardware Needed
15. Made by a Worship Pastor

**Descriptions:**
1. Put announcements, pictures and video on lobby TVs on a weekly loop. No designer needed.
2. One TV, a whole week: signs Monday to Saturday, kids content Sunday morning. Try it free.
3. Pair a Fire TV, Google TV or Roku with a six-character code. Schedule it from your phone.
4. Plays from saved content if the internet drops. Your logo and colours on the screen.

**Final URL:** `...&utm_content=signage_rsa1`  **Display path:** churchtvos.com / church-signage

### RSA 3: Slides and lyrics (Campaign C)
**Headlines:**
1. Church Slides on a TV (pin 1)
2. Song Lyrics Without a Laptop
3. Import a PDF or PowerPoint
4. Step Through From Your Phone
5. Church TV OS: Free Trial
6. For Chapels and Overflow Rooms
7. Themes That Look Like You
8. Songs, Pictures and Video
9. Countdowns Built In
10. Fire TV, Google TV, Roku
11. Volunteer-Proof Slides
12. Your Lyrics, Your Licences
13. Start Free, No Card to Look
14. Slides Without a Booth Laptop
15. Run Slides From Your Phone

**Descriptions:**
1. Build a deck once, run it on any TV. Songs with lyrics, pictures, video and countdowns.
2. Great for chapels, youth rooms and overflow. Not trying to replace your main stage rig.
3. Import slides from PDF or PowerPoint. Pick a theme. Press Next from your phone.
4. Your church adds the lyrics it is licensed to use. We keep the TV playing. Try it free.

**Final URL:** `...&utm_content=slides_rsa1`  **Display path:** churchtvos.com / slides

### RSA 4: Hardware-led (Campaign D)
**Headlines:**
1. Fire Stick for Church (pin 1)
2. Roku for Church Screens
3. Google TV for Church
4. Church TV OS: Free Trial
5. Use the TV You Already Have
6. Pair With a Six-Character Code
7. Kids, Signs and Slides
8. No Laptop Needed
9. Manage From Your Phone
10. Works on Fire TV and Roku
11. Live on Google TV Too
12. LG and Samsung Coming Soon
13. Start Free, No Card to Look
14. No Special Box Required
15. Keeps Playing Offline

**Descriptions:**
1. Kids rooms, lobby and slides on the Fire TV, Google TV or Roku you already have.
2. Pair with a six-character code. Schedule from the web. Run it from your phone.
3. Free to install, no ads. Start a free trial for your church. LG and Samsung coming soon.
4. Newer Fire sticks on Vega OS aren't supported. Other Fire TV, Google TV and Roku are.

## Assets and extensions
* **Sitelinks (25-char titles, 35-char descriptions):** "How it works" (Pair a TV in a minute) · "Kids rooms" (Playlists, countdowns, lyrics) · "Lobby signs" (Run on a weekly schedule) · "Slides" (Songs, decks, PDF import) · "Get the app" (Fire TV, Google TV, Roku).
* **Callouts (25 max):** Free trial · No ads in the TV app · Plays offline · Fire TV, Google TV, Roku · Run from your phone · Operator role for volunteers.
* **Structured snippets:** Types: Kids, Signage, Slides. Devices: Fire TV, Google TV, Roku.
* **Image assets:** `../08-graphics/out/og-1200x630.png`, `social-launch-1080x1080.png`, `feature-*.png` (1:1 and 1.91:1 where the console asks).
* **Call and location extensions:** not used.

## Conversion tracking (needs the privacy policy updated first)
* Use Google Ads tag only after consent handling is decided (a cookie banner may be needed if the Google tag sets cookies). Server-side `trial_started` / `tv_paired` events are preferable (strategy 03 section 7).
* No personal data in URLs or UTMs.

## Review cadence
* Weekly first month: search terms report; add negatives; pause any keyword with 15+ clicks and no trial.
* End of week 4: compare cost per trial with the $60 limit; end of week 8: go/no-go (strategy checkpoint 2027-04-26).
