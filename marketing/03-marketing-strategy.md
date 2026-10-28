# Church TV OS: Go-to-Market Strategy

Written 2026-10-23 for Keith Sparrow. Nothing in here has been posted, bought, sent or signed up for. Everything marked **VERIFY** is a claim I could not confirm from a primary source, or a number that is a hypothesis for you to decide.

## 0. Read this first (the honest summary)

1. **The wedge is hardware and price, not features.** The best-known competitor in kids rooms, Playlister, runs on Apple TV only and charges roughly US$20 to $40 per screen per month. Its own pricing page lists Lite at $19.99 annual / $21.99 monthly, Pro at $24.99 / $29.99 (includes an Apple TV), Apex at $39.99 / $41.99 ([playlister.app/pricing](https://www.playlister.app/pricing)). A search for Fire TV or Roku support found none ([faith.tools directory](https://faith.tools/for-kids), [Playlister's own streaming-device post](https://www.playlister.app/blog/a-raspberry-pi-comparison-apple-tv-vs-roku-vs-fire-stick)). A church with a $40 Fire stick, a Roku the youth room already owns, or a Google TV in the nursery is currently an underserved buyer. That is who to talk to first.
2. **You are not selling one product, you are selling one screen system.** Kids + Signage + Slides on the same TV, switching on a schedule, with a phone remote. Playlister sells kids playlists. OptiSigns and Yodeck sell signage. Proclaim and ProPresenter sell sanctuary slides. Nobody on that list sells "the TV you already have runs the nursery on Sunday and the lobby all week." Lead with the room and the person, not the feature list.
3. **Your most valuable asset is credibility, not budget.** You are a working worship pastor running this at a real church. A solo founder with a day job and a church job cannot out-spend anyone. You can out-trust them. Most of this plan is built on that.
4. **Search for marketing evidence was thin.** Private SaaS companies rarely publish what worked, and the search tools returned vendor pages and review sites more than case studies. Where I cite an example I say what it shows and what is inferred. Treat Section 2 as "patterns worth copying", not proven playbooks.
5. **Pricing is not set.** The pricing page on the site says "coming". You cannot run a founding-church offer, paid ads or a referral program without numbers. Decide pricing by about 2026-12-04 (Section 7 has a starting hypothesis).

---

## 1. What we are selling (from the codebase and store kits)

- **Church TV OS**, app id `com.churchtvos.tv`, dashboard at app.churchtvos.com, marketing site in `website/src`.
- **Modules:** Kids (playlists, countdowns, lyrics, YouTube, per-room scheduling, rotation), Signage (images, video, text signs, weekly slots, screen groups, portrait, live HLS), Slides (decks, songs, themes, video backgrounds, PDF/PowerPoint import, remote stepping).
- **Phone and Mac control:** remote, push message, Play now, status, offline alerts. iPhone, iPad and Mac apps are in beta (so: TestFlight, not "available now").
- **Platforms at launch (plan):** Fire TV (Amazon review in progress), Google TV / Android TV (same app; new personal Play accounts may need a closed test with about 12 testers for 14 days, VERIFY), Roku (BrightScript port built, never run on a real Roku, so launch date depends on device testing). LG and Samsung "coming soon".
- **Known limits to be honest about in copy:** newer Fire TV sticks on Vega OS cannot run it; YouTube slides do not rotate on portrait screens; the Roku app is new; Apple apps are beta; no integration with Orange, Planning Center or CCLI is live (do not imply otherwise).
- **Existing site copy** is already warm and plain ("Every screen at your church, run from your phone."). Keep that voice. The weakest spot is pricing and the "coming soon" platform story.

---

## 2. What worked for others (evidence and takeaways)

| # | Example | What it did | Why it likely worked | Steal this |
|---|---|---|---|---|
| 1 | **Playlister** ([home](https://www.playlister.app/), [pricing](https://www.playlister.app/pricing)) | Founder story (a church tech person replacing costly ProPresenter classroom setups, built 2018 per a third-party profile); a pricing page that sells a hardware bundle ("free Apple TV" promo code); "100+ reviews from Kids Pastors, 4.8/5"; named big-church testimonials; a "top reasons NOT to use Playlister" blog post framed as transparency; heavy blog SEO on curriculum comparisons ([Orange vs Grow](https://www.playlister.app/blog/orange-curriculum-vs-grow-which-is-better), [top 5 curriculum](https://www.playlister.app/blog/top-5-kids-ministry-curriculum)). | Solves a specific, painful Sunday problem, removes the hardware decision, and captures people searching for curriculum, not for "TV software". | Write comparison and "how do I run X curriculum on a TV" content. Offer a "just works" hardware answer (see Section 7). Publish an honest "who should NOT use us" page. |
| 2 | **Playlister x Orange** ([Orange announcement](https://thinkorange.com/blog/orange-partners-playlister-make-curriculum-easier-use/)) | Curriculum publisher partnership: content flows straight into the app, announced by the publisher. | Distribution through the brand kids pastors already trust. | A curriculum-publisher conversation is a long shot for you in 90 days, but a **small, independent curriculum publisher** or kids-ministry blogger partnership is realistic. Do not claim integration. |
| 3 | **Playlister x Tithely** ([Tithely partner page](https://get.tithe.ly/recommended/playlister)) | Tithely customers get a free Playlister screen. | Piggybacks on another vendor's customer list; trade of value, not a discount. | Pitch a "free screen for your customers" swap to a small church-software company (a website or app builder), not the giants. |
| 4 | **Playlister church-to-church sharing / free CKids curriculum (May 2026)** (search summary; VERIFY details) | Free curriculum and church-to-church sharing as a product-led growth loop. | Every shared playlist exposes another church to the product. | Later idea: let a church share a "deck pack" or signage template with another church by link. |
| 5 | **OptiSigns on ChurchLeaders** ([sponsored article](https://churchleaders.com/ministry-tech-leaders/390832-modernize-your-churchs-digital-signage-with-optisigns-digital-signage.html), [second](https://churchleaders.com/ministry-tech-leaders/399384-turn-any-screen-into-digital-signs-to-drive-engagement-in-your-congregation.html)) | Paid editorial in a church-leader publication; a church offer of about $10/month/screen and 25% off (per the article; VERIFY current); concrete use cases (QR code RSVPs, overflow-room live stream). | Meets church leaders where they already read; specific use cases, not feature lists. | Use the same use cases as video demos. A paid placement is probably out of budget; a **guest post** is not. |
| 6 | **Yodeck church page** ([yodeck.com](https://www.yodeck.com/solutions/church-digital-signage/)) | One screen free forever plus free church templates. | Lowers the first step to zero; templates are a lead magnet. | You need an equivalent: a free tier or a very long trial, and downloadable church-specific templates. |
| 7 | **Renewed Vision ProContent** ([ProPresenter free resources](https://renewedvision.com/blog/procontent-free-church-media)) | 1,000+ free media assets, with a paid library on top. | Churches search for backgrounds and motion loops constantly; free assets pull them in. | A free pack of **original** looping backgrounds, countdown loops and sign templates made by you, with a clear licence. |
| 8 | **Tithely referral program** ([get.tithe.ly/referral](https://get.tithe.ly:443/referral)) | Free to join, pays commission 30 days after the referred church processes over $200 (per their page; VERIFY terms). | Pays only on real activity; targets consultants, coaches and church-planting networks. | Referral that pays in free months, not cash (Section 6). |
| 9 | **Pushpay Goes (March 2026, search summary)** | Free tech foundation for church plants for a year. | Wins future customers when they have no budget; strong story. | A free first year for church plants and very small churches (one screen) is cheap for you and very good PR. |
| 10 | **Product Hunt solo launches** ([launch guide](https://app.getlaunchlist.com/blog/how-to-launch-on-product-hunt-2026), [zero-audience launch](https://www.producthunt.com/p/wrapt-ai/what-i-learned-launching-solo-on-product-hunt-with-zero-existing-audience)) | Guides say a waitlist supplies most launch-day traffic for top products; zero-audience launches land modestly (one founder #74 with 10 points). | Product Hunt rewards a pre-built audience. | Low priority for a church audience. Do a quiet listing for backlinks and tech-director curiosity; do not rely on it. |
| 11 | **Google TV in-app review prompt** ([Android Developers Blog, May 2025](https://android-developers.googleblog.com/2025/05/in-app-ratings-and-reviews-for-tv.html?hl=fi), [API guide](https://developer.android.com/guide/playcore/in-app-review)) | Official TV-supported prompt, D-pad friendly. | Ratings are the main TV store discovery signal. | Build it into the TV app, shown only when idle after real use, with no "would you rate us 5 stars" pre-question (Google forbids that). |
| 12 | **Amazon's own ASO guidance** ([Amazon developer blog](https://developer.amazon.com/apps-and-games/blogs/2024/06/app-store-optimization)) | Images do not rank directly but drive downloads; Fire TV needs 16:9 assets; users search by typing or Alexa voice, so title and voice-friendly naming matter. | Discovery on TV is thin and voice-driven. | Title that is easy to say aloud (see Section 8). |

**Gaps in the research:** I did not find public numbers for Planning Center, Pushpay, Subsplash, Proclaim or Church Media Squad marketing, nor Roku's current channel-promotion rules (the Roku sources were old forum posts and vendor blogs). Planning Center is known for a free public blog, tutorials and an active user community, but I could not cite a source here, so I have not built a tactic on it. I also could not confirm 2027 dates for church-tech or kids-ministry conferences. Known 2025 and 2026 events from search: CFX (Church Facilities Expo) by Church Production Magazine ([ISP Audio recap](https://www.isp-audio.com/en/installation-case-studies/places-of-worship/11921-more-than-140-exhibitors-gather-at-cfx-2025-to-drive-innovation-in-houses-of-worship)), WFX ([Live Design](https://www.livedesignonline.com/gear/wfx-conference-expo-training-products-and-more-for-house-worship)), Church IT Network national conference ([listing](https://www.sharedaudiences.com/events/church-it-network-national-conference-2026)). Church tech podcasts that surfaced: [Church Production Podcast](https://search.podderapp.com/podcast/the-church-production-podcast), [ChurchGear Podcast](https://www.audible.co.uk/podcast/The-ChurchGear-Podcast/B09SNJSKQ3), [Tech Arts Podcast](https://dgcm.podbean.com/page/2/). No pitch guidelines were found; check each site's contact page.

---

## 3. Positioning

**One line:** Church TV OS runs the screens at your church (kids rooms, lobbies, sanctuary) on the TVs and streaming sticks you already have, from your phone.

**Category we want to own:** "church screen system", not "digital signage" and not "kids video player". Signage is a commodity (Yodeck has a free screen). Kids playlists have a leader. The combination, plus Fire TV / Roku / Google TV, is the gap.

**Against each alternative (never name them in ads; see compliance):**
- vs Apple-TV-only kids tools: works on the sticks and TVs you already own.
- vs signage tools: knows what a Sunday morning is. Countdowns, lyrics, a room-by-room schedule, volunteers who can run it without breaking it.
- vs presentation software: no laptop in the booth for the nursery TV; a deck lives in the cloud and the TV plays it.
- vs "a laptop and an HDMI cable" (the real competitor for small churches): nothing to carry, nothing to forget, and it still plays if the Wi-Fi drops.

### Messaging pillars
1. **Use the TV you have.** Fire TV, Google TV, Roku (plus LG and Samsung to come). No proprietary box.
2. **Set it Thursday, forget it Sunday.** Schedule per room, downloaded ahead of time, keeps playing offline.
3. **Your volunteers can run it and cannot break it.** Operator role: next, back, blank, message. Cannot edit anything.
4. **One system, every screen.** The nursery on Sunday, the lobby all week, the sanctuary slides.
5. **Built by someone who runs Sunday.** Made at Forward Church, used at Forward Church.

### Tagline options (pick one, test two)
- **Run every screen at your church from your phone.** (closest to the current site headline; safe; best for search)
- **The TVs you already own, working all week.**
- **Sunday-ready screens, without the Sunday scramble.**
- **Kids rooms, lobbies and lyrics. One system.**
- **Plug in. Pair. Sunday's sorted.** (playful; the six-character code is the hook)
Avoid: "revolutionize", "transform your ministry", "AI-powered", and any phrase that sounds like a conference stage.

### Value props by persona
| Persona | Their real worry | Our promise | Proof to show | One-line pitch |
|---|---|---|---|---|
| **Kids pastor / director** | Rooms run on different laptops and USB sticks; volunteers fumble; curriculum changes weekly. | Each room is scheduled; the leader steps through from the remote or a phone; the countdown just runs. | 60-second video of a room set up Thursday and run Sunday; a volunteer-proof checklist. | "Every room's playlist is ready before you walk in." |
| **Tech director** | Another thing to support; fear of 30 devices dying on Sunday. | Offline caching, screen status, offline alerts, roles, campus scoping, sane hardware. | Status page screenshots; the "what happens when the internet drops" answer; fleet pairing. | "You can see every screen from your phone, and it keeps playing if the internet doesn't." |
| **Admin / executive pastor** | Cost, risk, who owns it, who has access. | Per-TV pricing you can budget; roles; one bill; privacy basics; export. | Pricing table, security and privacy page, access-by-campus. | "Predictable cost per screen, and staff only see what they should." |
| **Volunteer** | Fear of breaking something in front of 40 kids. | Big Next and Back buttons, a Blank button, nothing else to touch. | The phone remote screenshot; a 30-second "your first Sunday" clip. | "Press Next. That's it." |
| **Small church with one TV** | No staff, no budget, one display in a fellowship hall. | One screen, one phone, free trial; announcements on weekdays, lyrics or slides on Sunday. | A 3-minute "set up one TV tonight" video; price for one screen. | "Your one TV can do announcements all week and lyrics on Sunday." |

---

## 4. Launch calendar

**Assumptions (change if wrong):**
- **L-day (launch day) = Tuesday 2027-01-26.** Rationale: January is when churches plan spring and rebuild volunteer teams, it is after Christmas, before Lent and Easter (Easter is 2027-03-28), and gives about 13 weeks to finish pricing, Stripe, store approvals and Roku device testing. If Roku testing slips, **launch on Fire TV and Google TV and treat Roku as "Launch 2" three to four weeks later** rather than delaying everything.
- Amazon review is already in progress; the Google closed test (if required) must start by about **2026-12-10** to finish before L-day.
- Time budget: **6 to 8 hours a week for marketing**, rising to about 10 in launch week. If you have less, drop Section 5 tiers, not the waitlist.

### Phase A: Foundations and waitlist (2026-10-23 to 2026-11-30, L-95 to L-57)
| Date | Action |
|---|---|
| By 10-30 | Pick tagline. Add a **waitlist form** to every page of the site, with a platform question (Fire TV / Google TV / Roku / LG / Samsung / not sure), role and church size. Add analytics (Section 9). Set up email tool with double opt-in (CASL). |
| By 11-06 | Record **Forward Church "customer #1" baseline**: today's pain, screens, volunteers, time spent weekly. Take before/after photos. Start a proof folder (Section 7). |
| By 11-13 | Publish **"Coming to Roku, LG and Samsung"** page with its own waitlist, and a "Fire TV and Google TV" availability note. Honest dates: "We're in store review" until approved. |
| By 11-20 | Publish the first 3 SEO posts and the **pricing page with real numbers** (even if "founding price"). |
| By 11-27 | Record the 3 core demo videos (Section 5). Set up YouTube channel. Join (do not post in) 5 to 8 relevant Facebook groups. |
| 11-30 | Waitlist goal: **150 signups** (hypothesis; see KPIs). |

### Phase B: Closed beta and proof (2026-12-01 to 2027-01-08, L-56 to L-18)
- Start Google closed test (about 12 testers) with Forward Church staff and 8 friendly churches from your network (written consent for any quote later).
- Invite **15 to 25 beta churches** from the waitlist and your relationships. Give them a direct line to you. Goal: **10 churches with a TV paired and used on a Sunday**.
- Collect 5 short written quotes and 2 video testimonials with signed permission (Section 7).
- Run Roku device testing. Decide Roku in/out for L-day by **2027-01-08**.
- Avoid Dec 20 to Jan 1 for any sends: church staff are on holiday.

### Phase C: Pre-launch push (2027-01-09 to 2027-01-25, L-17 to L-1)
- Email the waitlist weekly: sneak peek, setup video, founding-church offer deadline.
- Outreach to 10 to 15 church-tech and kids-ministry bloggers/podcasters (one personal email each, no mass send; CASL-safe because it is one-to-one, relevant and identified; see Section 10).
- Submit the store listings polished (Section 8). Pre-write all launch-week posts.
- Confirm Stripe and trial flow works end to end. Test the "pair a TV" first-run on a brand-new Fire stick and a new Google TV device.

### Phase D: Launch week (Mon 2027-01-25 to Sun 01-31)
| Day | Action |
|---|---|
| **Mon 1-25** | Final checks. Schedule email. Tell Forward Church staff and your beta churches the news a day early. |
| **Tue 1-26 (L-day)** | Email the waitlist ("It's live. Here's the 3-minute setup."). Post launch video on YouTube, Facebook page, Instagram, LinkedIn. One post in each relevant Facebook group only where rules allow, as a **story plus free resource**, not an ad. Update site: store badges live; Roku/LG/Samsung marked "coming". |
| Wed 1-27 | Post the Forward Church case study. Reply to every comment and DM same day. |
| Thu 1-28 | Live Q&A on YouTube or Zoom (30 minutes): "Set up your first Church TV OS screen with me." Record it. |
| Fri 1-29 | Short "what we learned this week" post. Ask beta churches to leave honest store reviews if they used it (no incentives, Section 8). |
| Sat/Sun | Rest. Check support inbox Sunday evening. |

### Phase E: First 90 days (2027-01-26 to 2027-04-26)
- **Weeks 1 to 4 (Jan 26 to Feb 22):** convert trials; onboarding emails; weekly short video; fix the first-run friction your analytics show. Launch Roku if delayed. Quiet Product Hunt listing.
- **Weeks 5 to 8 (Feb 23 to Mar 22):** Lenten / Easter angle: **"Easter Sunday screen checklist"** guide (a lead magnet, dated to ship by 2027-03-01). Referral program goes live. Start paid tests at the $500 tier if you choose it.
- **Weeks 9 to 13 (Mar 23 to Apr 26):** Easter 2027-03-28 is your biggest proof moment: collect photos and quotes from churches that used it for Easter. Post-Easter, publish "What we learned running Easter on Church TV OS." Pitch summer VBS use (signage plus countdowns), and fall planning articles from May.
- **Checkpoint 2027-04-26:** go/no-go review on channels. Cut anything that produced less than 1 trial per 5 hours of effort.

### Ongoing (from May 2027)
- Weekly: 1 video, 1 post per channel, 1 email every 2 weeks.
- Monthly: 1 SEO article, 1 customer story, 1 product-update email.
- Seasonal hooks: VBS (April to June), fall kickoff (July to Aug), Christmas Eve (from Nov), Easter (from Feb), new year (December).
- Annual: evaluate one conference; ask customers for reviews at renewals.
- Enter **LG and Samsung** on their store timeline: waitlist email, a launch micro-campaign each.

---

## 5. Channel plan

### Content pillars (use these for everything)
1. **Sunday setup** (how-to): "Set up your first TV", "Schedule a rotation", "Add song lyrics".
2. **Real rooms** (proof): Forward Church photos, volunteers using the remote, before/after.
3. **Practical church-tech** (teaching, not selling): "What to do when the Wi-Fi drops on Sunday", "Portrait TV in a lobby".
4. **Behind the build** (founder voice): "I'm a worship pastor who built this. Here's why."
5. **Offers and updates** (low volume): new features, founding offer, store news.

### Per-channel tactics

**Facebook groups (highest trust, zero cost, easy to get wrong)**
- Rules: read the rules and **ask the admins first** (one DM). Many groups ban self-promotion outright ([EOFire on "no self-promotion"](https://www.eofire.com/what-no-self-promotion-means-facebook-group-guidelines/)); some allow a weekly promo thread. Never post a link in a group that bans it.
- Do 3 weeks of pure helping before ever mentioning the product: answer "how do I run curriculum in the nursery without a laptop" with a genuine answer (even if the answer is "use a Fire stick and any tool").
- Disclose in the first line: "I built a tool for this, so take my view with salt."
- Offer a **free resource** (setup checklist, background pack) rather than a pitch. Answer in comments; no hard sell.
- Your own **Facebook page + a small "Church Screen Setups" group** (photos of church screen setups, signage ideas, no sales). Cheap community you own.
- Cadence: 15 minutes a day, 5 days a week. Target: 3 to 5 helpful comments a day, 1 resource post a week where permitted.
- Children's ministry privacy: never post photos with identifiable children; follow your church social media policy ([children's ministry guidance](https://childrensministry.com/?p=93470)).
- Expected outcome: 20 to 40 waitlist signups per month once trusted. KPI: group-sourced signups tracked by `utm_source=facebook_group`.

**YouTube (your searchable asset)**
- Target viewers searching a problem, not our name. Titles: "How to put kids church videos on a Fire TV", "Church lobby digital signage on a $40 Fire Stick", "Run song lyrics on a TV without a laptop".
- Formats: 3 to 8 minute screen-record tutorials with your voice; 60-second Shorts cut from them; a monthly "what's new".
- Cadence: weeks 1 to 8, 1 per week; then 1 per two weeks. Description links with UTM. Chapters on every video.
- Video list (first 10): (1) What it is, 90 seconds; (2) Pair a TV in 60 seconds; (3) Kids room: schedule a week of curriculum; (4) Lobby signage: weekday loop; (5) Slides: a song and a sermon title; (6) Phone remote for volunteers; (7) What happens when the internet drops; (8) Portrait TV in a lobby; (9) Fire TV vs Google TV vs Roku for church; (10) Forward Church walkthrough.
- Expected: slow burn; 500 to 2,000 views in the first 90 days is a realistic range (hypothesis). KPI: view-to-site clicks, 3 to 5 percent.

**Instagram and TikTok (short video)**
- Not where kids pastors buy, but where they scroll and share. Repurpose YouTube Shorts: before/after of a room, the countdown on a TV, "6-character code" reveal, "volunteer proof" clips.
- Cadence: 3 per week on Instagram Reels, same clips on TikTok if time allows. If time is tight, **do Instagram only**.
- No children's faces. Photograph screens, not kids.
- Expected: awareness; very low direct conversion. KPI: profile visits and link clicks.

**LinkedIn (tech directors, executive pastors, church admins)**
- Founder voice, 2 posts a week: a build story, a church-tech lesson, a customer result. One article per month.
- Connect with tech directors and church administrators; message only after they engage.
- Expected: warm conversations, a few demos. KPI: demo requests.

**Reddit**
- Subreddits to read first: r/churchtech or similar, r/ChurchMedia, r/Fire_stick, r/digitalsignage, r/Roku, r/kidsministry (VERIFY the exact names; I did not search them). Reddit punishes promotion harder than Facebook.
- Rule: 9 helpful replies for every 1 mention; always disclose; never post the same text twice; no DM spam.
- Cadence: 20 minutes, 3 times a week. Treat it as listening and SEO (Reddit threads rank in Google).
- Expected: handful of signups, but excellent for product insight.

**Email and newsletter outreach**
- Own list: waitlist, beta churches, anyone who emailed. Double opt-in, with CASL-compliant footer.
- Sequences in Section 9.
- Other people's newsletters: **sponsorships** (small church-tech newsletters) are best at $500+/mo; at zero budget, offer a guest tip.

**Church-tech podcasts, bloggers, publications**
- Targets: [Church Production Magazine / podcast](https://search.podderapp.com/podcast/the-church-production-podcast), [ChurchGear Podcast](https://www.audible.co.uk/podcast/The-ChurchGear-Podcast/B09SNJSKQ3), [Tech Arts Podcast](https://dgcm.podbean.com/page/2/), Church IT Network, ChurchLeaders' ministry-tech section, kids-ministry blogs and YouTubers, and church-tech YouTubers who review gear.
- Pitch angle (one email, no attachments): "Worship pastor builds a TV system for his own church; here's what he got wrong and learned." Offer: a free account for the host and a 15-minute story, not a product demo.
- Target: 10 pitches in pre-launch, 2 to 3 appearances in 90 days (hypothesis).

**Conference and partner plays**
- Do not buy a booth in year one. Instead: (a) **attend one event as a visitor** (a regional church-tech or kids-ministry event) and put 20 conversations on a list; (b) **offer a 10-minute lightning talk** at a regional event ("Your church already owns the screens"); (c) ask Church IT Network members for 20 minutes to demo. Check [WFX](https://www.livedesignonline.com/gear/wfx-conference-expo-training-products-and-more-for-house-worship), [CFX](https://www.isp-audio.com/en/installation-case-studies/places-of-worship/11921-more-than-140-exhibitors-gather-at-cfx-2025-to-drive-innovation-in-houses-of-worship) and the Church IT Network conference for 2027 dates and exhibitor costs (**VERIFY; I could not confirm 2027 dates**).
- Partner types: church website/app builders (swap a "free screen for your customers" like Playlister did with Tithely), AV integrators who install lobby TVs (give them a referral fee or free account; they hate software support), denominational networks, church-plant networks, curriculum bloggers.
- Webinars: **one per month**, 30 minutes: "Set up your church screens in 30 minutes". Co-host with a partner when possible; record and upload to YouTube.

**Google Ads and Meta Ads (only after you have a working first-run and tracking)**
- Search keywords to test (Google, phrase and exact match): "church digital signage", "kids ministry video player", "church lobby tv software", "church slides on fire tv", "church song lyrics display tv", "sunday school tv app", "church announcement screen", "fire tv for church", "roku for church signage", "church countdown timer for tv". Negative keywords: free movies, IPTV, jobs, Plex, templates (unless you want them).
- Do **not** bid on competitor names (Section 10).
- Meta audiences: interests (Christianity, church administration, children's ministry), job titles (children's pastor, tech director, church administrator), lookalike from waitlist (once 100+). Creative: a 15-second screen-recording of pairing a TV; headline "Your church TV, run from your phone".
- Landing: dedicated page per persona with UTM and a single CTA (start free trial / join waitlist).
- Expected: church software CPCs tend to be $1 to $4 and conversion to trial 3 to 8 percent (hypothesis, VERIFY with your own data). Stop any campaign above $60 per trial.

**SEO content (write once, benefit for years)**
Target keywords (hypothesis; validate with a keyword tool before writing):
- "church digital signage" / "digital signage for churches"
- "how to display song lyrics on a TV at church"
- "kids church video player", "sunday school video playlist"
- "church lobby screen ideas", "church announcement slides"
- "fire stick for church", "church tv app fire tv", "church signage roku"
- "church countdown timer video"
- "how to run church slides without a laptop"
- "portrait digital signage church"
Content list (first 10 posts, 800 to 1,500 words each, with a screenshot or short clip): the setup guide for each platform; "Best hardware for church screens (Fire TV vs Google TV vs Roku vs Apple TV, with honest trade-offs)"; "What to put on a church lobby screen: 15 ideas"; "Church signage on a budget"; "Volunteer-proof Sunday: a screen checklist"; "How we run kids rooms at Forward Church". Include a **comparison page** that is fair and uses factual, dated claims only ("verified on 2026-10, VERIFY").

**App store optimization (ASO), by store**
- **Amazon Appstore / Fire TV:** Amazon says visuals boost downloads and rank indirectly, and Fire TV needs 16:9 assets; search is typed or by Alexa, so the title should be speakable ([Amazon](https://developer.amazon.com/apps-and-games/blogs/2024/06/app-store-optimization)). Put the first paragraph of the description to work (users rarely tap "more", per a Vimeo onboarding doc). Keep the existing keywords (church, signage, digital signage, kids, classroom, display, announcements, lyrics, countdown), and consider "slides", "sunday school" and "worship". Use 5 to 9 screenshots that each show a real screen with a one-line caption.
- **Google Play (Google TV / Android TV):** publish to Android TV form factor only; short description with the primary keyword in the first 80 characters; TV banner and feature graphic; use the Play In-App Review API on TV after meaningful use ([Android Developers Blog](https://android-developers.googleblog.com/2025/05/in-app-ratings-and-reviews-for-tv.html?hl=fi)).
- **Roku:** Roku's own forum notes a keyword field in channel info and that search was limited to select partners at the time of the post (old; VERIFY current rules). Pick a name and description with searchable words, a clear thumbnail, and consider Roku's own advertising later only if budget allows.
- **All stores:** title "Church TV OS" is short and speakable; consider a subtitle or short description that says what it does: "Kids rooms, church signage and slides".
- **A/B copy test:** change the first line of the description every 4 weeks and watch installs.

### Budgets and expected outcomes

| Level | Spend | Where it goes | Time | What to expect by day 90 (hypotheses) |
|---|---|---|---|---|
| **Zero** | $0 (excluding existing domain/hosting) | Facebook groups, YouTube, LinkedIn, Reddit, email to your own list, 1 podcast pitch a week, SEO | 7 to 8 hrs/wk | 300 waitlist, 60 trials, 12 to 20 paying churches (assumes each trial has ~25 to 35 percent conversion and good onboarding) |
| **~$500/mo** | $500 | $200 Google Search ads on 8 to 10 exact-match keywords; $100 Meta retargeting on site visitors; $100 for a freelance video editor for Shorts; $100 for stock/tools (email, keyword tool, scheduling) | 8 to 10 hrs/wk | 450 waitlist, 100 trials, 25 to 40 paying churches |
| **~$2,000/mo** | $2,000 | $800 Google Ads; $400 Meta; $400 sponsorship in one church-tech newsletter or podcast per month; $400 editor/designer | 10 to 12 hrs/wk plus contractor help | 900 waitlist, 200 trials, 50 to 80 paying churches. Cap spend if trial-to-paid is under 15 percent. |

These are **planning numbers, not predictions**. Conversion rates for church software are not publicly documented in any source I found. Recompute after the first 4 weeks of real data.

### Posting cadence summary (zero-budget level)
| Channel | Weekly effort | Output |
|---|---|---|
| Facebook groups | 75 min | 15 to 25 helpful comments, 1 resource |
| YouTube | 2 hrs | 1 video (week 1 to 8), then 1 per 2 weeks |
| Instagram | 30 min | 3 Reels (repurposed) |
| LinkedIn | 30 min | 2 posts |
| Reddit | 60 min | 5 to 10 replies |
| Email | 45 min | 1 email per 2 weeks to list |
| Outreach | 60 min | 5 personal pitches (podcasts, bloggers, churches) |
| SEO | 90 min | 1 article every 2 weeks |

---

## 6. Offers

- **Free trial:** keep the current model. Recommend **30 days** with all three modules and 2 TVs, no card. Extend to 60 days for the first 25 beta churches. Add a "Pair your first TV" checklist in the dashboard and an email at day 1, 3, 7, 14, 25.
- **Founding-church offer (limit: first 50 churches):** locked-in price for **24 months** (or "as long as you stay subscribed"; decide), a direct line to you, and a vote on the roadmap (e.g. Planning Center integration, LG/Samsung timing). Cap the number to keep the scarcity honest.
- **Pricing hypothesis (YOUR decision):** per module, per TV. Starting idea for a founding price: **Kids $9, Signage $5, Slides $5 per TV per month**, or an all-modules bundle at **$15 per TV** with volume breaks. That sits well under Playlister's $19.99 to $24.99 per screen for kids alone, and a Fire stick costs far less than an Apple TV. Test whether $9 makes the product look cheap; kids pastors compare to $20+. A $12 kids price may be easier to defend than being the cheapest.
- **Nonprofit angle:** every customer is a church or nonprofit already. Say so plainly and do not pretend to a special "nonprofit discount" unless it is real. A good honest angle: **free for church plants in their first year and for very small churches (1 screen)**, similar to [Pushpay Goes](https://www.fintechfutures.com/press-releases/pushpay-announces-new-product-innovations-to-help-streamline-ministry-operations-and-increase-engagement-in-the-church) (March 2026). Cost to you is small; PR value is high.
- **Referral program:** "Give a month, get a month." The referring church gets one free month per referred church that pairs a TV and stays 30 days; the new church gets 30 extra trial days. Avoid cash; avoid per-sign-up rewards that tempt fake accounts. Offer AV integrators and consultants a separate, written, **disclosed** referral arrangement.
- **Hardware helper:** a "buy this stick" page (Fire TV Stick 4K or similar, Google TV Streamer, Roku) with affiliate links, if you want. **Disclose affiliate links clearly.** Do not stock or ship hardware at launch.
- **Forward Church as customer #1:** It is the best asset you have. Treat it as a **case study with real numbers**, not a testimonial from yourself. See below.

### Proof and testimonials to collect (real only)
Collect from Forward Church staff and 5 to 10 beta churches. For each: **written permission** (a short email saying "yes, you may quote this with my name and church"), date, role.
- Before/after: "How we ran kids rooms before" (laptops, USB sticks, who did it) and after.
- Hard numbers: minutes saved per Sunday, number of screens, number of volunteers trained, number of campuses, Sundays without a failure.
- A volunteer quote on how easy the remote is.
- 30-second video of a room on Sunday morning (no identifiable children; screens only or backs of heads with parent permission through your church's own policy).
- Screenshots of the dashboard with real (not fabricated) data.
- A reference-call list of 3 churches willing to talk to prospects.
**Never** invent a quote, name, logo, number of churches, or ratings. Where you have no proof, say "built at Forward Church and tested in 9 rooms" only if that is literally true.
Also hold the **written note from Forward Church leadership** confirming Church TV OS is your product and Forward is a customer (already on your HANDOFF list). Do it before publishing any case study naming the church.

---

## 7. Funnel and measurement

**Funnel:** Awareness (video, search, group helpfulness) → Site visit → **Waitlist or free trial** → Account created → Church created → TV paired (the activation moment) → Content scheduled → Ran on a Sunday → Paid → Referred another church.

**The one metric that matters early:** **TVs paired and played on a Sunday** within 14 days of sign-up. Everything before that is vanity.

**Landing pages needed:** (1) Home (exists). (2) Pricing with numbers. (3) "Coming soon: Roku, LG, Samsung" with waitlist. (4) Persona pages: /kids-ministry, /church-signage, /church-slides, /small-church. (5) Comparison and "who it is not for" page. (6) Case study: Forward Church. (7) Founding-church offer with a live counter only if it is accurate. (8) A simple **"Get the TV app"** page with store buttons and platform detection.

**Waitlist fields:** email (required), church name, role, number of TVs, platform (Fire TV, Google TV, Roku, LG, Samsung), interest (Kids, Signage, Slides), how they heard. Add a "consent to receive emails about Church TV OS" checkbox (unticked) for CASL (Section 10).

**Analytics:** use a privacy-friendly tool (Plausible, Fathom or self-hosted equivalent; check that it does not set tracking cookies so you can skip the cookie banner), plus events: waitlist_submitted, trial_started, tv_paired, first_content_scheduled, first_sunday_play, plan_purchased. Do not put personal data in URLs. Server-side events from Supabase for the product milestones.

**UTM scheme** (all lowercase, no spaces):
- `utm_source` = facebook_group | facebook_page | youtube | instagram | tiktok | linkedin | reddit | email | podcast | partner | google | meta | referral
- `utm_medium` = organic | paid | email | social | video | referral
- `utm_campaign` = launch2027 | waitlist | easter2027 | vbs2027 | roku_launch | founding50
- `utm_content` = specific asset (e.g. `pairing60s`, `lobbyloop`, `checklist`)
- `utm_term` = keyword (paid search only)
Example: `https://churchtvos.com/?utm_source=youtube&utm_medium=video&utm_campaign=launch2027&utm_content=pairing60s`
Keep a simple spreadsheet mapping each link you create.

**Conversion goals and targets (hypotheses; adjust after 4 weeks of data):**
| Stage | Target |
|---|---|
| Site visit → waitlist/trial | 4 to 8 percent from warm traffic, 1 to 3 percent from cold |
| Trial → TV paired | 50 percent |
| Paired → paid | 25 to 35 percent |
| Referred churches per paying church | 0.2 in year one |
| Churn | under 3 percent monthly |
| Support time per church | under 30 minutes in the first month |

**Email sequences (build once, automate):**
1. **Waitlist welcome** (immediately): what we're building, what platform you chose, what to expect; ask one question: "What do you run on your TVs today?" (replies are gold).
2. **Waitlist nurture** (weekly in the last 6 weeks): sneak peek, setup video, honest status update, founding-offer deadline.
3. **Trial onboarding** (day 0, 1, 3, 7, 14, 25): pair a TV; schedule your first room; give the remote to a volunteer; what to do if the internet drops; invite a colleague; trial ending, with a human sign-off.
4. **Post-purchase** (day 7, 30, 60): referral invite, review request (no incentive), "what would you build next?"
5. **Win-back** (day 45 and 90 after cancel): one short note, no guilt.
Sender: your name and address; plain-text style; a real postal address in the footer.

---

## 8. Store launch and review generation

**Titles and copy**
- **Fire TV:** Title "Church TV OS". First paragraph of the long description should read well alone: "Run your kids rooms, lobby signage and Sunday slides on Fire TV. Pair with a six-character code and schedule everything from the web or your phone." The existing short description is good. Add the "free demo mode, no account needed" line high in the text.
- **Google Play:** Title "Church TV OS: Kids, Signage, Slides" if allowed (VERIFY policy; metadata must not be misleading or keyword-stuffed).
- **Roku:** Name "Church TV OS", keywords in the description (church, kids, signage, slides, announcements, lyrics).
- **Images:** screenshots must be of real screens, not mock-ups with false claims. Add a one-line caption on each. Lead with the best three (the countdown, the lobby sign, the lyrics).
- **Video preview** (if the store allows): 20 to 30 seconds, no voiceover needed.

**Ratings and reviews (ethical only)**
- Add the **Google in-app review prompt** on Google TV ([guide](https://developer.android.com/guide/playcore/in-app-review)): show when the TV UI is idle, after meaningful use (say, after 3 completed Sundays), at most once per period, and **no pre-question** like "Do you like this app?", which Google disallows.
- On Fire TV and Roku, add a QR code in the app's settings screen linking to the store page. Email beta and trial churches **after** they have used it on a Sunday: "If it helped, a short honest review helps other churches find it."
- **Do not** pay for reviews, gift in exchange for 5 stars, or ask only happy users in a way that gates reviews. I did not find Amazon's official review-solicitation policy; **VERIFY** before sending any review email.
- Reply to every public review, positive or negative, within 48 hours.
- Target: **15 honest reviews in 90 days** (hypothesis), then ask again at day 180.

**Launch mechanics for each store**
- Submit **at least 10 days before L-day** to allow rework. Amazon, Google and Roku can reject for small things (metadata, demo mode, permissions).
- Have a reviewer note in each store with demo mode steps and a review account (already written in `store/AMAZON-SUBMISSION.md` and `store/GOOGLE-PLAY-SUBMISSION.md`).
- Release **staged** on Google Play (10 percent, then 50 percent) if available.
- Keep a **plan B** page: if one store is late, the site should still work with "Available on Fire TV and Google TV. Roku next."
- Mark LG and Samsung **"coming soon"** with a waitlist, not a date. Do not promise a date you do not control.

---

## 9. 30/60/90-day action list for a solo founder

### Days 1 to 30 (2026-10-23 to 2026-11-22)
**Keith must do personally**
1. Decide L-day, tagline and pricing hypothesis (1 hour). Write down what "founding church" means.
2. Get a signed/emailed note from Forward Church leadership (ownership and customer status).
3. Record 3 demo videos in your own voice; take Forward Church photos.
4. 15 minutes a day in 5 to 8 Facebook groups (helping only); DM admins to ask about promo rules.
5. Personally email 10 church-tech friends / kids pastors you know, with a plain, warm message.
6. Start 5 to 8 beta-church conversations.
**Claude/automation can do**
- Draft the waitlist form, the email sequences, SEO outlines and first drafts (you edit the voice), the UTM sheet, comparison and persona pages, store listing text, social caption drafts, a content calendar.
- Build analytics events and the waitlist-to-email connection.

### Days 31 to 60 (2026-11-23 to 2027-01-22)
**Keith**
- Finish beta with 10 churches; run weekly 20-minute calls with 3 of them.
- Record testimonials (with written permission).
- Send the pitch emails to podcasts and bloggers (one by one).
- Submit stores; approve listings; do Roku device test.
**Automation/Claude**
- Draft the launch-week posts, emails and the case study from your notes; build the "Easter screen checklist" PDF; schedule social posts; set up the email automations; prepare the review-request email and the in-app prompt spec.

### Days 61 to 90 (2027-01-23 to 2027-03-23, covering launch)
**Keith**
- Launch week: show up in comments, run the live Q&A, answer emails personally.
- First customer calls; collect the next 5 quotes.
- Decide whether to start the $500 tier based on trial-to-paid.
**Automation**
- Welcome and onboarding sequences run themselves; weekly reporting spreadsheet (visits, waitlist, trials, TVs paired, paid); weekly digest of Facebook/Reddit mentions (use free alerts, do not scrape).

### What must be personal vs automated
| Must be Keith | Can be automated or delegated |
|---|---|
| Replying in groups and comments in your voice | Scheduling posts, resizing images, captions drafts |
| Customer calls and demos | Email sequences, reminders, review requests (after you approve) |
| Testimonial permission, relationship with partners | Report building, keyword research, SEO drafts |
| Final say on claims, pricing and compliance | Editing videos (freelancer), thumbnails |
| Showing up live (Q&A) | Support FAQ and templated replies |

**Rule of thumb for time:** if a marketing task needs more than 90 minutes per week and has produced nothing in 4 weeks, stop it.

---

## 10. Compliance and risk notes

**Church and nonprofit sensitivity**
- Don't use manipulative urgency, guilt, or "God told us" framing. No fear-based copy about falling behind other churches.
- Don't imply spiritual outcomes ("grow your church") you cannot back. Say what the product does: "keeps your screens running."
- Run all copy through your own sense of what you would be comfortable saying at your church. Use the Forward Church comms and statement-of-faith skills if the copy speaks for Forward Church, and remember that **Church TV OS is yours personally**: do not use Forward Church's brand, logo or name as if the church endorses the product without their written agreement.
- Be careful with a pastor's authority: don't use your role at Forward Church to pressure other churches or staff.
- Avoid any photo or video of children without parental permission; follow your church's policy.

**CASL (Canada's Anti-Spam Legislation) for email**
- Commercial electronic messages need **consent, sender identification and a working unsubscribe**. Fines can reach CAD $10 million for organizations ([summary](https://mailmodo.com/guides/canada-anti-spam-law); these are vendor summaries, **VERIFY with the CRTC site or a lawyer**).
- **Express consent:** waitlist form with an unticked checkbox, plain language ("Email me about Church TV OS"), your identity, address and unsubscribe. Keep a record (date, wording, source). Use double opt-in.
- **Implied consent:** limited cases (a customer, or an inquiry, typically 6 months for inquiries per the summaries; VERIFY). **Conspicuous publication** of a work email can support implied consent for relevant messages only, and you must be able to prove it.
- Never buy lists. Never email a cold list "to see what happens." One-to-one personal emails about a clearly relevant topic are still commercial messages if they promote the product; identify yourself and include an unsubscribe.
- Honour unsubscribes quickly (the law gives 10 business days; do it immediately).
- If you email US recipients, also follow **CAN-SPAM** (postal address, honest subject, opt-out).

**Privacy**
- Publish a privacy policy that matches reality (the store kits already list none of advertising IDs, analytics SDKs, or location). Keep that true: if you add pixels (Meta, Google Ads), update the policy and the data-safety answers in each store **before** launching ads.
- Canadian PIPEDA applies to you as a Canadian business; US state laws may apply to US customers. Don't collect children's data. The TV app collects a device ID only.
- Cookie banner: choose a cookie-free analytics tool and you may not need one; if you use ad pixels, add consent.
- Never put personal data in URLs or UTM parameters.

**Testimonials and claims**
- No fake testimonials, invented logos, inflated church counts or purchased reviews. Real names only with written permission. Date every metric. "Used by Forward Church" is fine if true; "Trusted by churches everywhere" is not.
- No unproven claims about competitors.

**Trademark: Playlister and competitors**
- Do not use **Playlister, Orange, Proclaim, ProPresenter, Planning Center, Pushpay, Subsplash, OptiSigns, Yodeck** in ad keywords, ad copy, store keywords, app metadata or page titles. Using competitor names in store metadata is a common rejection reason and a trademark risk (not legal advice; **check with a lawyer before comparison ads**).
- On your own site, **nominative, factual comparison** (naming them to compare) is safer than in ads: use accurate, dated, sourced statements; don't imply endorsement, don't copy their logos, don't use their screenshots, and offer to correct errors. A neutral phrase like "Apple TV-based tools" is safer than a brand name in headlines.
- Do not claim integrations with Orange, Planning Center, CCLI or MultiTracks until they exist and you have permission.

**Music and curriculum copyright**
- Church TV OS plays what the church uploads. Say in the terms and onboarding that **the church is responsible for having the licenses** for lyrics (for example CCLI), recorded music, video and curriculum it uploads, and for streaming and display rights.
- **Do not** ship, promote or host copyrighted songs, backgrounds, curriculum videos or Orange/other publisher content. Marketing assets must use your own original content, properly licensed stock, or Forward Church content you own. Don't use copyrighted worship songs in promo videos (including YouTube Shorts: Content ID can mute or claim them).
- Check each curriculum's licence before telling churches they can upload it to a cloud service.
- The free background pack: only original or properly licensed assets, with a licence file.

**Other**
- Keep a clean separation of Church TV OS accounts from Forward Church accounts (already your plan).
- Keep refund and cancellation terms clear and visible.
- Accessibility: captions on videos and alt text on images (also good SEO).
- Keep **honest store claims**: don't say "works on all TVs". The Vega OS limit and the new Roku build belong in the copy.

---

## 11. Sample copy (to edit into Keith's voice)

**Homepage subhead:** "Your kids rooms, lobby and Sunday slides on the TVs you already have. Pair with a six-character code. Run the room from your phone."

**Facebook group helper post (only where allowed):**
> "A few of us were talking about nursery TVs. We got tired of USB sticks and laptops, so I built a way to run kids videos, countdowns and lobby announcements from a Fire stick, scheduled from the web. Happy to share the setup checklist we use at Forward, no strings. Disclosure: I'm the one who made the tool."

**Cold-ish email to a podcast host (one-to-one):**
> "Hi [name], I'm a worship pastor in Cambridge, Ontario. I built a TV system for our kids rooms and lobby because the tools I found only ran on Apple TV. A lot of churches I talk to have Fire sticks and Roku boxes. I'd be glad to share what I got wrong. No pitch needed. If it's useful for your listeners, I'll give you a free account to try. If not, no worries. [unsubscribe/identity line]"

**Waitlist confirmation:**
> "Thanks for joining. Which TVs do you want to run: Fire TV, Google TV, Roku, LG or Samsung? Reply and tell me what you use today, I read every one."

---

## 12. Risks and what to watch

| Risk | Mitigation |
|---|---|
| Launch slips (Roku untested, store rejections) | Soft-launch on Fire TV and Google TV; treat Roku as Launch 2 |
| Solo time runs out in launch week | Pre-write posts; cap channels at 4; use the "stop after 4 weeks" rule |
| Pricing mismatch | Founding price locked for 24 months; test with beta churches before publishing |
| Ads before activation is solid | Don't spend until first-run onboarding works and trials get paired |
| Support overload on Sundays | Support hours posted; self-serve FAQ; a Sunday-only emergency email |
| A competitor reacts | Stay factual, focus on platform breadth and price |
| Reputation risk if something fails at a church on Sunday | Offline caching, "what happens if the internet drops" content, honest status page |

**Sources cited above:** playlister.app (home, pricing, blog), thinkorange.com partnership post, get.tithe.ly (Playlister and referral pages), faith.tools, churchleaders.com (two OptiSigns articles), yodeck.com church page, renewedvision.com ProContent, Amazon developer blog on ASO, Android Developers blog and docs on in-app review, Product Hunt launch guides, ISP Audio / Live Design / Church IT Network event pages, church-tech podcast listings, CASL summaries. Unverified items are flagged **VERIFY** throughout.
