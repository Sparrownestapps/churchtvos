# Church TV OS: Market Research

Research date: 2026-10-23. Research only; nothing was posted, signed up for, or sent.
Confidence labels: **[V]** = seen on a vendor/primary page this session; **[T]** = third-party or competitor-authored claim; **[E]** = my estimate or inference; **[?]** = could not verify.

---

## 0. Executive summary

1. **The closest analog, Playlister, is Apple TV only** [V]. Its own pricing page says it runs on the "Playlister Screen" app from the tvOS App Store. Church TV OS's Fire TV / Google TV first approach is a genuine hardware-cost gap: Playlister's own comparison page quotes a roughly $149 Apple TV [V], versus a Fire TV stick that is a fraction of that [E, check current Amazon price].
2. **Playlister is the incumbent to beat on kids ministry**: it claims 10,000+ churches in 53 countries [V, vendor claim; the figure is repeated by faith.tools, not independently audited], price of $19.99 to $39.99 per screen per month [V], strong curriculum ties (Orange sync, booth at the Orange Conference) [V], and a content engine (podcast, blog, Facebook-group roundups, G2/Trustpilot reviews) [V].
3. **The most dangerous price competitor is FreePlay (ChurchApps)**: free, open source, runs on Fire TV, Android TV and Apple TV, offline playback, scheduled mode [V]. It has no signage or slides depth, and no adoption numbers are published [V]. It sets a "free" anchor that Church TV OS must out-value.
3b. Playlister's most repeated criticism is **price that scales per classroom** (G2 reviewer paying 4x their ProPresenter licence for 7 screens) [T, via search summary of G2; the G2 page itself returned 403 to me].
4. **Nobody found combines all three jobs** (kids-room playlists + lobby signage + sanctuary slides) on cheap Android TV hardware with a phone remote and portrait support. Playlister does kids + basic signage on Apple TV; Look/OptiSigns/Yodeck/ScreenCloud/Rise are signage only; ProPresenter/Proclaim are slides only and need a computer.
5. **Market is large but small-church-heavy**: roughly 350,000 US congregations, median attendance about 65-70 [V]. Median-size churches rarely have 10 kids rooms, so the sweet spot is likely **100-1,000 attendee churches with 2-12 screens** [E].
6. **Best channels** (details in Section 5): Facebook groups (kids ministry + church tech), Orange / kidmin conference ecosystem and curriculum-provider communities, Planning Center community, a "Playlister alternative / Fire TV" SEO content play, app-store listings, and a handful of podcasts/newsletters. Reddit is low-volume for this audience [E].

---

## 1. What Church TV OS is today (from the repo)

Sources read: HANDOFF.md, PROGRESS.md, APPS-PLAN.md, SLIDES-MODULE-PLAN.md, website/src/pages (home, for-churches, pricing), store/AMAZON-SUBMISSION.md.

- **Modules**: Kids (curriculum playlists: video, countdown, lyrics, YouTube), Signage (images, video, slideshows, weekly schedule, groups, portrait), Slides (decks, themes, song library with lyrics auto-split, backgrounds, countdown, HLS live feed; PDF / PowerPoint / picture import; experimental NDI).
- **Mixed TVs**: one screen can switch modules on a schedule (signage weekdays, Kids Sunday).
- **Hardware/platforms**: Fire TV first (app id `com.churchtvos.tv`), then Google TV/Android TV, then Roku; LG/Samsung "coming soon". Pairing by 6-character code. Offline caching.
- **Control**: web dashboard (app.churchtvos.com), TV-remote operation, planned iPhone remote and Mac app (planning stage per APPS-PLAN.md; the website already shows them, so check that marketing copy matches what has shipped).
- **Multi-church / multi-campus**: organizations, sites, rooms, roles (owner, admin, editor, operator), per-church branding.
- **Pricing**: not set. Plan is per module + per TV; website says free trial, no card, "pricing on the way". Forward Church is customer #1 on an internal plan.
- **Status**: Appstore submission kit prepared; website live; no external customers or reviews yet [E, none recorded in the files].

Implication: the product's differentiators are breadth (3 modules), cheap hardware, phone remote, portrait/multi-campus, and import of existing PDF/PPTX. Its weaknesses vs incumbents are no brand, no curriculum partnerships, no reviews, no Planning Center integration (not mentioned in the files), and no Apple TV (a large share of church kids-ministry deployments, since Playlister and Orange's APlay are Apple TV based).

---

## 2. Competitor and analog landscape

### 2.1 Summary table

| Tool | What it is | Target | Pricing (verify before quoting) | Platforms | Overlap with Church TV OS |
|---|---|---|---|---|---|
| **Playlister** | Cloud kids-ministry playlist player + basic signage + livestream to rooms | Kids ministries, multi-campus | Lite $19.99/screen/mo annual ($21.99 monthly); Pro $24.99 ($29.99), includes Apple TV; Apex from $39.99 ($41.99). 30-day trial [V] | Apple TV only; web admin; iPhone/iPad companion [V] | Kids (direct), Signage (partial) |
| **FreePlay (ChurchApps)** | Free open-source TV app for lesson content | Any church, especially small | Free, "no cost, ever" [V] | Fire TV, Android TV incl. ONN, Apple TV; not Roku [V] | Kids (direct, free) |
| **Amazing Life APlay / Amazing+** | Curriculum company's playlist tools bundled with curriculum | Churches buying Amazing curriculum | Bundled with curriculum subscription; no price seen [?] | Web player + Apple TV casting [T] | Kids (curriculum-locked) |
| **Orange (APlay / Church Conference / content)** | Dominant kids curriculum brand; syncs into Playlister | Orange Kids churches | n/a | n/a | Channel and partner, not a competitor |
| **ProPresenter (Renewed Vision)** | Industry-standard presentation software | Production/AV teams | $29/mo or $289/yr per seat; 14-day trial; ProPresenter Remote included [V]. Older listing: $399 licence [T] | Mac/Windows computer | Slides |
| **Proclaim (Faithlife/Logos)** | Cloud church presentation | Small to mid churches | Logos says from $20/mo or $200/yr; Capterra lists $24.99-$92.99 tiers [V/T conflict]; free version | Computer; has remote and Apple TV/Android player [E] | Slides |
| **Planning Center Services** | Service planning; integrates with ProPresenter | Most US churches | Priced by team size; free tier "5 team members" [V]; no signage product found [?] | Web/mobile | Not a competitor; the planning source of truth |
| **Look Digital Signage** (lookdigitalsignage.com; I could not find any separate "Mlook.tv" so this may be the same or a sister product, unverified) | Cloud signage with a church landing page | Churches, schools, businesses | From $6/screen/mo; 14-day trial [V] | Android, Windows, Linux, Tizen, webOS, Raspberry Pi [V] | Signage |
| **OptiSigns** | General signage; free tier | Broad; used by churches | Free for 3 screens (logo shown); Standard $10 ($9 annual), Pro $12.50, Pro Plus $15, Engage $30, Enterprise $45 (25-screen min) [V] | Fire TV, Android, Windows, Mac, Pi, Apple TV (limited), Tizen, webOS [T] | Signage |
| **Yodeck** | Signage built around Raspberry Pi | Budget single-screen | Free for 1 screen; $8 / $12 / $16 per screen/mo [V via Rise Vision, a competitor] | Pi, Android, Windows, Tizen, webOS, Signage Stick; Fire TV limited [T] | Signage |
| **ScreenCloud** | Corporate signage | Larger orgs | Core $20, Pro $30 per screen/mo annual; 14-day trial [V] | Broad, no Apple TV [T] | Signage |
| **Rise Vision** | Calendar-driven signage, K-12 roots | Schools, nonprofits | Basic $11/mo or $119/yr per display (nonprofit same as K-12); Enterprise $164/yr [V via its own blog] | Android, Windows, Chrome OS, Apple TV, Signage Stick [T] | Signage |
| **Kitcast** | Signage with native Apple TV and Fire TV | Churches/orgs | From $7/screen/mo, Pro $10; no free tier; 14-day trial [T, self-published ranking] | 9 platforms including Fire TV, Apple TV | Signage |
| **DigitalSignage.com** | Free-for-small signage claim | Small churches | "First 3 screens free" [T] | Android stick | Signage |
| **SignPresenter** | Signage/content; a FreePlay content provider | Churches | Pricing not published (G2 says none provided) [V/?] | n/a | Signage, content |
| **Church Media Squad** | Not found in searches | n/a | [?] | n/a | Unverified |
| **Subsplash, Pushpay, Tithe.ly, Ministry Brands** | Giving, apps, ChMS, streaming | All church sizes | Varies | n/a | No lobby/kids TV product found in searches [?]. They matter as distribution partners and conference sponsors, not direct competitors |
| **Church Online Platform** | Free online-service platform | Online campuses | Free | Web | Not a competitor |
| **Free DIY**: USB drive, laptop, YouTube, Chromecast | The real incumbent in small churches | Everyone small | $0 | Anything | The main thing you replace |

### 2.2 Detail on the most relevant players

**Playlister (closest analog)**
- Founders Kevin Smith (CTO, built v1 at his Indiana church) and Grant Glas (CEO); origin: replacing ProPresenter machines in 10 classrooms with an Apple TV app [V, playlister.app/why-we-made-it].
- Claims 10,000+ churches, logos include Hillsong, Elevation, NewSpring, Cross Point; "100+ reviews from Kids Pastors" at 4.8/5; G2 reportedly 219 reviews; Trustpilot overwhelmingly 5-star on an older, small sample [V/T].
- Features: cloud playlists, scheduling by room, roles/tag permissions, offline play, YouTube import, Orange curriculum sync, livestream (Resi/HLS) to overflow rooms, signage loops, MDM/SSO on higher tiers, "Church-to-Church" content sharing (May 2026) [V/T].
- Hardware: Pro rents a managed Apple TV; Lite requires the church's own. Playlister promo: code "apple" gives $160 off [V].
- Marketing playbook (copy-worthy, legally and ethically as a pattern, not content): "ProPresenter alternative" landing pages with cost math (claims $239/yr vs ProPresenter $399 + $159/yr and a ~$1,749 computer), blog roundups of Facebook groups and podcasts, its own podcast ("Playback"), Orange Conference booth giveaways of an Apple TV, G2/Trustpilot/faith.tools listings, free 30-day trial, demo booking [V].
- **Weaknesses to exploit**: Apple TV lock-in and $149+ hardware per room; per-screen cost that "adds up quickly across many classrooms" [T, learnofchrist review]; reviewer on G2 reported paying about 4x a ProPresenter licence for 7 screens [T]; admin can't take a unit out of Playlister Mode, duplicate linked libraries [T]; reliance on tech-savvy volunteers to upload and troubleshoot (per a competitor's page, Yippee, so treat as biased) [T]; Capterra review noted it "doesn't integrate well into a large group space" [T, 2019]; Mon-Fri 9-5 ET support on Lite/Pro (weekend support only on Pro) [V]; no sanctuary slide/lyric deck builder [E]; no mention of Planning Center on its origin page [V].
- **Do not copy**: its marketing claims verbatim, the Playlister name, or its G2 scores.

**FreePlay (ChurchApps, 501(c)(3), published by Live Church Solutions)** [V]
- Free, offline-first, Fire TV / Android TV / Apple TV; scheduled mode via admin.freeplay.church; plan pairing; announcements loop; providers: Lessons.church (about 1,100+ free lessons), Bible Project, SignPresenter, B1.church, Jesus Film, Dropbox/OneDrive.
- It is "a TV app, not a phone app", no Roku [V]. No adoption numbers [V].
- Church TV OS cannot win a price war with free. It wins on: managed support, multi-module use of the same screen, slides/songs, phone remote, branding, roles/permissions, portrait, and "works with the curriculum you actually bought" (upload your own). Consider also whether it could be a content *source* (check licence) rather than only a rival [E].

**Signage tools (OptiSigns, Yodeck, Look, ScreenCloud, Rise, Kitcast)**
- Cheap ($6-$20 per screen/month) and mature. They compete on lobby/hallway signage and have templates, apps and giving QR codes. They do not do curriculum playlists with leader-controlled playback, song lyrics, or a service deck. Church TV OS should position signage as the "included" use of a screen, not the headline.
- Amazon's own **Signage Stick** (about $100, partner roster of about 86 CMS apps per an Oct 2026 German report; reportedly US-only for now) has OptiSigns, ScreenCloud, Yodeck, Rise etc. as partners [T]. Amazon has no CMS of its own [T]. Handoff notes already flag looking into this program; being a listed partner would be a distribution channel [E, requirements unverified].

**ProPresenter / Proclaim**
- ProPresenter is what media teams already own; its pain points are crashes, training and computer-per-room cost (Capterra rating 4.6 from about 2,085 reviews, cons: bugs/crashes [T]). Proclaim is cloud-friendlier and cheaper.
- Church TV OS Slides should not try to replace the main-sanctuary production workflow for big media teams. It targets: small and mid churches without a dedicated ProPresenter operator, overflow rooms, kids rooms, chapels, multi-campus satellites, and secondary screens [E].

### 2.3 Gaps Church TV OS can exploit (ranked)

1. **Cheap, common hardware**: Fire TV / Google TV vs Apple TV-only Playlister. Biggest tangible gap. Pitch total cost of a 6-room rollout [E, compute with current prices at launch].
2. **One system for the whole week**: kids on Sunday, lobby signage all week, slides in the sanctuary, mixed on one TV. Competitors are single-purpose.
3. **Price vs Playlister**: pricing is undefined, so Keith can deliberately undercut per-screen cost or offer a flat per-campus tier and a free tier for 1 to 2 screens to answer FreePlay and OptiSigns.
4. **Phone remote** (iPhone/Mac): Playlister has an iPhone/iPad companion [V], FreePlay does not [V], most signage tools have no live "next/back" control. Only market it when shipped.
5. **Portrait, multi-campus time zones, roles** and branding: strong in the spec, matter to mid-sized multi-site churches.
6. **PDF/PPTX import**: lets a church reuse existing curriculum slides; Playlister's own materials describe the "building presentation files" pain [V].
7. **Planning Center integration** (not in the files): the single most requested integration category in church tech [E]; ProPresenter has one [V]. Worth prioritizing for marketing credibility.
8. **Canada/UK/Australia friendliness**: Playlister support hours are Eastern time Mon-Fri [V]; Keith is in Cambridge, Ontario (Canadian pricing, CAD, Canadian denominational channels such as PAOC, EFC), a plausible local wedge [E].
9. **Roku and Samsung/LG** later: breadth FreePlay (no Roku) and Playlister (Apple only) lack.

### 2.4 Risks and honest cautions
- Free alternatives (FreePlay, Yodeck 1 screen, OptiSigns 3 screens, DigitalSignage.com 3 screens, USB drive) cap willingness to pay for small churches [V/T].
- Curriculum content rights: kids ministry value depends on curriculum (Orange, Amazing, Lessons.church etc.). Without partnerships, Church TV OS is "bring your own content" like Playlister Lite. Playlister's Orange sync is a moat for Orange churches [V].
- Fire TV platform risk: Amazon moving Fire TV toward its own Vega OS; OptiSigns notes Vega isn't supported and some older sticks have auto-start problems [T]. Test your support matrix.
- Trust: children's ministry content and child safety raise the bar; reviewers flag vendor dependence and data policy detail [T].

---

## 3. Market size

### 3.1 Number of congregations

| Region | Estimate | Source / confidence |
|---|---|---|
| **United States** | About 350,000 religious congregations; Hartford/FACT 2020 survey covered 15,000+ congregations from 80 denominations [V/T via news summaries] | goodfaithmedia, churchleaders, NPR 2026 (see sources). Counting methods vary; other estimates range higher [E] |
| **US Protestant/Christian subset** | Most of the 350k [E]; Planning Center says 90,000+ churches use it, and Stripe's page calls it over 25% of a market of 350,000+ churches [T] | faith.tools / Planning Center site / Stripe |
| **Canada** | Roughly 18,000-30,000 congregations depending on definition. EFC says about 24,000 Christian congregations, almost half evangelical; a 2015 Faith Today piece says about 30,000; United Church alone 2,404 in 2024 [T]. The 23,580 / 45,996 numbers on B2B database sites are unreliable [?] | EFC, Faith Today, United Church |
| **UK** | About 50,500 churches/congregations in 2017 (Brierley), about 50,700 in 2010; figures are old [T] | BRIN |
| **Australia** | About 11,400 local churches in 2016, down about 1,200 since 1991 [V] | NCLS |
| **Total English-speaking core** | About 430,000+ [E, sum of the above] | |

### 3.2 Size distribution

- **US median**: 65 attenders in 2020 (FACT); rose to about 70 in late-2025 fieldwork per a Hartford report covered by NPR in April 2026 (first rise in about 25 years, self-reported; I could not open the NPR page, figures are from the search summary) [T].
- NCS 2018-19: median congregation 70 participants and $100,000 budget; the average attendee sits in a congregation of 360 and about 91% of congregations are smaller than 360 [T, summary of Duke NCS].
- Mainline median 50; evangelical median 65; Catholic/Orthodox median 200 [T].
- **Australia (NCLS)**: median 50; mean 128; 47% under 50 attenders; 5% over 500; 155 churches over 1,000 [V].
- Church size matters because kids rooms, lobbies and sanctuary screens appear mostly in churches of about 100+ [E].

**My addressable-market estimate (clearly an estimate, not sourced)**: perhaps 10-20% of US congregations (35,000-70,000) are large enough (about 100+ attenders) to have a dedicated kids room and a lobby screen worth paying for [E]. If 10,000+ churches already use Playlister (vendor claim) and 80,000-100,000 use Planning Center, the premium-segment paid TV tools clearly have a few tens of thousands of reachable churches. Worldwide, much larger.

### 3.3 Kids ministry and signage prevalence
- **Kids ministry**: I did not find a current national percentage. Barna 2005: 95% of Protestant churches ran planned Bible instruction in a class setting; classes for ages 2-5 at 88% [V, old, Protestant-only, n=614 pastors]. NCS 2018-19 asked about children's programs but I could not retrieve the number [?]. Treat "most churches above ~75 attenders have some kids programming" as an estimate [E].
- **Digital signage**: no reliable adoption percentage found [?]. NCS 2018-19 shows screens/projectors/video in worship are more common in larger congregations; exact figures not retrieved [?].
- **Tech adoption trend**: Pushpay/Barna State of Church Technology 2025 (1,700+ leaders): 86% use church management software; 67% use an app. 2026 edition (1,300+ leaders): 94% say tech helps the Church fulfill its mission; 75% say it improved connection [V/T]. More than half of respondents were from congregations under 200, so findings skew small [T]. AI adoption is fast but policy lags (Exponential: 61% use AI weekly/daily; only 6% have a policy; Pushpay: 33% use AI in ministry or operations) [T].
- **Post-COVID**: median attendance fell from 137 (2000) to 65 (2020) and 45 during COVID before a modest rebound [T]. Screens/streaming became more normal in churches.

Action: if sizing precision matters for investors, buy or request the full Pushpay State of Church Technology report and the Lifeway/Barna data tables; both appear to gate their detail.

---

## 4. Where these tools are found and used

### 4.1 Discovery channels used by Playlister and peers (evidence)
- **Product-led / search**: free account + 30-day trial + Calendly demo; "ProPresenter alternative" and "kids ministry TV" solution pages; faith.tools directory listing (categories include Church Resources and For Kids) [V].
- **Review sites**: G2 (219 reviews reported), Trustpilot, Capterra (a single old verified review), endorsal.io [T]. Reviewers praise volunteer ease of use; complaints centre on price.
- **Conferences**: Playlister runs a booth at the Orange Conference with an Apple TV + free-year giveaway [V]. Orange Conference is now called "Church Conference" (April 28-30, 2026, Dallas) per Tithe.ly's list [T].
- **Content marketing**: own podcast "Playback" (bi-weekly, host Grant Glas), blogs ranking Facebook groups and podcasts for kids ministry, YouTube and Instagram [V].
- **Curriculum ecosystems**: Orange Kids Facebook community (including questions about uploading to Playlister); testimonials from Eagle Brook, New Hope and Church on the Move (Tulsa; a 500-seat church that started in one classroom then rolled out) [V]. The Church on the Move case study shows the typical adoption path: production-team member researches, tests in **one room**, expands [V].
- **Word of mouth among kids pastors** (peer recommendation in Facebook groups) [E, strongest signal but not quantified].
- **Freeplay/ChurchApps**: distributed through church-tech/open-source goodwill, B1/Lessons.church ecosystem, GitHub [V/E].

"How did you hear about us" data: not published by any of these vendors that I could find [?]. Review pages show *why* people bought (volunteer simplicity, time saved: one Yippee-quoted "9 hours weekly" claim [T, competitor page]) not how they found it.

### 4.2 Communities (with sizes where verified)

**Church tech / media Facebook groups** (member counts from a Playlister blog listing, self-reported, date unknown) [T]:
- Church Sound & Media Techs (CSMT): about 77,800
- Church Creatives: about 51,300
- CMG Community (formerly Visual Church Media, Church Motion Graphics): about 42,900
- Church Social Media Managers: about 37,000
- Churches That Live Stream: about 21,400
- Canva for Church: about 7,700
- Church Communications group: about 25,000+ (The Creative Pastor list)

**Kids ministry Facebook groups** (Playlister list; counts mostly unstated) [T]:
- Orange Kids: A Community for Children's Ministry Leaders (top-ranked on that list)
- I Love Kidmin Community (KidzMatter)
- Stuff You Can Use: A Children's Ministry Community (under-resourced churches)
- Children's Ministry Network
- Children's Ministry Connect (CMConnect), almost 2,000 members
- Small Church Kid's Min group; PAOC regional kids ministry groups (BC & Yukon, Saskatchewan, Eastern Ontario/Nunavut) [T]
- Denomination or curriculum groups (e.g., CRC Dwell leaders) [T]
- Note: the best groups ban or throttle promotion. Rules must be read before any posting [E].

**Reddit**: r/churchtech exists and is "open to all questions related to tech used in church" [T]. I could not fetch Reddit or find subscriber counts; no useful kids-TV threads surfaced in search [?]. Other likely subs: r/Pastors, r/ChurchMedia, r/kidsministry. All unverified for size/activity; Reddit tends to be hostile to promotion, so participation (answering questions) beats ads [E].

**Podcasts** (kids ministry): Kids Ministry 101 (Lifeway), Orange Kids Podcast, Kidmin Talk (Kidology, Karl Bastian), KidzMatter Podcast, Nick Blevins Family Ministry Podcast, Cross Formed Kidmin, Kids Ministry Circle, Simple Kidmin (Jason Byerly), Developing Leaders Impacting Kids [T, ministry-to-children.com, Playlister blog lists]. Feedspot lists 34 kids ministry podcasts [T].

**Church tech media/podcasts/newsletters**: ChurchTechToday.com (Kenny Jahng; free weekly newsletter; monthly podcast accepting sponsors; contact info@churchtechtoday.com; audience size not found [?]); Church Production Magazine / Church Production Podcast (inactive per Podder, 34 episodes) [T]; Church Tech Weekly (Mike Sessler; long-running, vendor partnerships such as Audinate) [T]; Ministry Brands podcast (episode on tech/media tips) [T]; Church Online podcast [T]; The Lead Pastor (publishes conference and tech lists) [T]; Church Leaders "ministry-tech-leaders" section [T]; Faith Tools Substack (directory of Christian tech) [T].

**YouTube**: Pro Church Tools (Brady Shearer), Churchfront (Jake Gosselin), Ryland Russell [T, via a Substack roundup]. Subscriber counts not verified.

**Planning Center community**: integration partner listings (ProPresenter is listed) [V]. I did not verify partner-program terms; the PCO API limits are noted in Keith's memory for other projects [?].

### 4.3 Conferences (2026 data from Tithe.ly, The Lead Pastor, ChurchTechToday; dates may shift; many already passed as of 2026-10-23)
| Event | Date / place | Audience | Relevance |
|---|---|---|---|
| Orange Conference / "Church Conference" | Apr 28-30, 2026, Dallas | Kids, family, student ministry | Highest relevance for Kids module; Playlister already there |
| KidzMatter Conference | Oct 6-8, 2026, Evansville IN; 170+ breakouts | Children's/youth leaders | High (kids) |
| Church IT Network (CITN) | Oct 4-6, 2026, Louisville; about 500 attendees | Church IT, ChMS admins, production | High (tech decision-makers) |
| SALT Conference | Oct 14-16, 2026, Irving TX | Worship leaders, tech directors | High |
| Experience Conference (EC26) | Sep 8-11, Orlando | Worship/creative/tech | Medium |
| Rooted Conference | Oct 22-24, Brentwood TN; small | Youth, children, family | Medium |
| FILO Conference | May 5-6, 2026, Willow Creek | Production and tech volunteers | Medium-high |
| NRB International Christian Media Convention | Feb 17-20, 2026, Nashville | Christian media | Low-medium |
| CFX + Capture | Sep 14-16, Birmingham AL | Facilities, production | Medium (signage) |
| RightNow | Nov 4-6, Dallas | Discipleship / media | Low |
| Echo Conference, Church Tech Conference, Exponential, Cultivate, Kidmin-specific events | Not found in search results [?] | | Check manually |
Costs: attendee tickets $95-$800; booths are far more [?] and not researched. Booth/sponsor pricing not found; I'd treat conferences as *later*-stage unless Keith attends as a visitor [E].

### 4.4 App stores and listings
- Amazon Appstore (Fire TV), Google Play (TV), Roku Channel Store: the TV app is free to install; discovery through store search is weak for B2B, but a clean listing, privacy policy and screenshots establish credibility (the submission kit is ready).
- Directories: faith.tools (Playlister is listed there), G2, Capterra, GetApp, Software Advice, Slant, AlternativeTo, Product Hunt (low-yield for churches) [E].

---

## 5. Ranked channel recommendations

Scale: audience size (what I could verify), cost, effort for a one-person founder. All costs [E] unless cited.

| Rank | Channel | Why | Audience | Cost | Effort |
|---|---|---|---|---|---|
| 1 | **Kids-ministry and church-tech Facebook groups** (participate, answer, post a clearly labelled "beta, looking for 10 churches" thread only where rules allow; ask admins first) | This is where Playlister buyers discuss tools; peer recommendation is the primary discovery path [E]. | Church Sound & Media Techs 77.8k, Church Creatives 51.3k, CMG 42.9k, Orange Kids (unstated), CMConnect about 2k [T] | Free | Medium, weekly |
| 2 | **SEO / content: "Playlister alternative for Fire TV", "kids ministry TV without Apple TV", "church digital signage on Fire TV Stick", "free vs paid kids ministry TV app", cost calculators** | Playlister proves search demand with its "ProPresenter alternative" pages; Fire TV is a wedge its content ignores. Evergreen. | Search | Free to low | Medium up-front, compounding |
| 3 | **Founding-church program via Keith's network**: Forward Church as case study; invite 10-20 churches in Ontario/Canadian denominations (PAOC, Baptist, CRC, Alliance, EFC contacts); free for a season in exchange for testimonial and feedback | Church on the Move's path (test one room, expand) shows trust is built by pilot; case studies are what G2/Capterra reviews and blog posts need. | A few dozen churches | Free tier cost | High-touch |
| 4 | **Kidmin podcasts as guest/pitched story** (Simple Kidmin, Kids Ministry Circle, KidzMatter, Orange Kids Podcast) and **church-tech podcasts/newsletters** (ChurchTechToday newsletter/podcast, Church Tech Weekly) | Credible reach to kids pastors and tech directors; story angle: "built by a worship pastor to fix our own kids-room TVs; offline, cheap hardware". | Unverified per show | Free to sponsorship [?] | Low-medium |
| 5 | **Planning Center community / integration listing** | Planning Center claims 90k+ churches [T]; integration is a trust signal and a feature gap. Not verified how partner programs work. | 80k-100k churches | Dev time | High dev, high payoff |
| 6 | **Review platforms**: G2, Capterra, GetApp, Software Advice, faith.tools listing | B2B church buyers read reviews; Playlister leans on G2/Trustpilot [V]. Needs real customers first. | Search | Free (paid ads optional) | Low once customers exist |
| 7 | **YouTube**: tutorial videos (pair a Fire TV in 2 min, build a kids playlist, make lobby signage from a PDF), plus outreach to church-tech YouTubers (Churchfront, Pro Church Tools) | Church volunteers learn tools by video; also feeds SEO. | Unverified | Free (time) | High |
| 8 | **Conferences** (CITN, KidzMatter, SALT, FILO; later Orange/Church Conference) | Face-to-face trust; Playlister uses Orange booths [V]. Attend first, exhibit later. | CITN about 500; others unspecified | Tickets $95-$800 [T]; booths [?] | High |
| 9 | **Reddit** (r/churchtech, r/Pastors, r/ChurchMedia, r/kidsministry): helpful answers, no ads | Cheap awareness, but audience size unverified and promotion-hostile [E] | Unverified | Free | Low |
| 10 | **Paid ads** (Facebook/Google, retargeting to trial signups) | Only after onboarding is proven. Target job titles (Children's Pastor, Kids Director, Tech Director, Executive Pastor). | Scalable | Start about $300-$1,000/month [E] | Medium |
| 11 | **Partnerships**: curriculum providers (Lessons.church / ChurchApps, smaller indie curricula, Canadian denominational curricula), ChMS or giving vendors (Planning Center, Subsplash, Tithe.ly) | Content and distribution. Verify licensing before promising "built-in curriculum". | n/a | Rev share or none | High, slow |

**Highest-yield first 90 days [E]**: (a) list on faith.tools and prepare G2/Capterra/GetApp profiles; (b) publish 5 comparison/tutorial pages; (c) recruit 10 pilot churches from Keith's networks; (d) join 5 Facebook groups as an observer, then helpful participant; (e) pitch 3 podcasts after the pilot has a story; (f) ship a Planning Center integration or at least a "Planning Center-friendly" story.

**Hashtags/accounts [E, unverified popularity]**: #kidmin, #kidsministry, #childrensministry, #churchtech, #churchmedia, #churchproduction, #churchcommunications, #worshiptech; follow/engage with Orange (thinkorange), KidzMatter, Lifeway Kids, Kidology, Churchfront, Pro Church Tools, ChurchTechToday, Planning Center, Church IT Network. Instagram/TikTok are low-yield for this B2B audience; LinkedIn is useful for executive/admin pastors and denominational staff [E].

**Decision-makers to reach**
- **Kids pastor / children's ministry director**: feels the Sunday pain; champions the Kids module; often influences or owns a small budget.
- **Tech/media/production director (staff or volunteer lead)**: evaluates hardware, offline, networks, support; veto power.
- **Executive/admin/operations pastor or church administrator**: approves recurring spend, compares price per screen, wants multi-campus roles.
- **Lead pastor / campus pastor**: cares about visitor experience, lobby, branding; signs off in smaller churches.
- **Volunteers (room leaders, A/V teams)**: end users; their ease-of-use feedback decides renewal.
- **Denominational or network staff** (regional kids ministry leaders, e.g. PAOC district kids ministry networks): multiplier channel [E].

---

## 6. Buyer personas, pain points, positioning

### 6.1 Personas

**1. "Overloaded Kids Director" (primary, Kids module)**
- Church of 150-1,000, 3-12 kids rooms; uses Orange / Amazing / custom curriculum; USB drives, laptops, YouTube.
- Pains (confirmed by Playlister case study): weekly file downloads and renaming, laptops and adapters in each room, volunteers who cannot mirror a screen, mismatched rooms, last-minute failures [V]. Fear of ads or wrong content on YouTube [T].
- Triggers: new classroom/TV, volunteer burnout, growth, a Sunday failure.
- Objections: price per room; "will volunteers manage it"; "does it work with our curriculum"; "what if wifi dies" (answer: offline cache).

**2. "Volunteer Tech Director" (gatekeeper)**
- Media/AV lead; knows ProPresenter and Planning Center; wants control, reliability, remote management.
- Pains: ProPresenter licences/computers per room, crashes, training new volunteers [T]; Apple TV cost; hardware sprawl; network setup (a Trustpilot reviewer got locked out of wifi by a managed Apple TV setup [T]).
- Needs: fleet status, roles, auto-update, MDM-ish management, kiosk auto-launch (the Appstore submission must keep this opt-in).

**3. "Executive/Admin Pastor" (budget owner, multi-site)**
- Wants predictable cost per campus, consistent branding, minimal staff hours, role-based access, audit.
- Pains: per-screen pricing that "adds up quickly" [T], tool sprawl (separate signage, kids, slides), vendor lock-in.

**4. "Small-church Pastor / Admin" (long tail)**
- 50-120 attenders, 1 lobby TV and a small sanctuary screen, perhaps 1-2 kids rooms, almost no budget. Competes with free (FreePlay, Yodeck free, OptiSigns free). Needs a generous free tier or a flat low price; this segment is a volume/community play, not a revenue play [E].

**5. "Multi-campus communications lead"**
- Central team pushes series art and announcements to all campuses, with local overrides; time zones; one dashboard (Look's church page describes exactly this need [V]).

### 6.2 Positioning angles (choose one primary)
1. **"Every screen at your church, on the hardware you already have."** (breadth and cheap hardware) Pair with a total-cost table vs Apple TV per room.
2. **"Kids-room TV without the Apple TV tax."** Sharp, comparison-led, targets Playlister's sore spot; keep claims factual and date them.
3. **"Sunday-proof."** Offline caching, leader control, countdown, no Wi-Fi panic. Reliability story that matches the Church on the Move pain.
4. **"One TV, a whole week."** Kids Sunday AM, signage Mon-Sat, slides for midweek; improves ROI per TV.
5. **"Built by a church staff member for volunteers."** Keith is a worship pastor at Forward Church; authenticity and a Canadian base; support hours that include weekends [E; Playlister weekend support is Pro only [V]].

### 6.3 Messaging to avoid
- Do not claim "replaces ProPresenter" for sanctuary production; claim "simple slides for the rooms and churches that don't need a production rig".
- Do not show prices in iOS apps (per APPS-PLAN); keep billing on web.
- Do not use competitor logos, G2 scores, or promo codes. Comparison pages must cite sources and dates.
- Remove or mark "coming soon" any feature not shipped (iPhone/Mac remote, Roku, LG/Samsung).

### 6.4 Pricing implications (for Keith's decision; not a recommendation to adopt)
- Reference points per screen/month: Playlister $19.99-$39.99; ProPresenter $29/seat; Look from $6; Kitcast from $7; Yodeck $8; OptiSigns $9-$15; Rise $11; ScreenCloud $20-$30; FreePlay $0.
- A per-module, per-TV model needs a visible **bundle** (e.g., all three modules on one TV at one price) to differentiate from single-purpose tools, and a **free or very low tier** (1-2 screens) to meet FreePlay/Yodeck/OptiSigns and generate reviews [E].
- Consider campus-based caps for multi-site churches to avoid the "adds up quickly" complaint [E].

---

## 7. Open questions and verification list (things I could not confirm)

1. Playlister's real number of paying churches (10,000+ is vendor claim) and its Fire TV roadmap [?].
2. G2/Capterra pages blocked for me (403); counts and quotes came from search summaries. Re-read directly before quoting.
3. Mlook.tv and Church Media Squad: no results found; may be rebranded, small or defunct [?].
4. Current kids-ministry and signage adoption percentages (NCS IV report tables, Lifeway, Barna) [?]. The NCS IV PDF was too large to fetch; read it locally for exact numbers.
5. Facebook and Reddit member counts and promotion rules; Reddit could not be accessed [?].
6. Podcast/newsletter audience sizes and sponsorship rates [?]; conference booth pricing [?].
7. Planning Center partner/integration process [?]; Amazon Signage Stick partner requirements and non-US availability [?].
8. Current Fire TV Stick / Apple TV prices and Fire TV's roadmap (Vega OS) [E/T].
9. Canada/UK/Australia church counts are old or definition-dependent; use as ranges.
10. Subsplash/Pushpay/Tithe.ly/Ministry Brands signage products: none found, but not exhaustively checked [?].
11. Whether Echo, Church Tech Conference, Exponential, Cultivate have 2026-27 editions and relevant audiences [?].

---

## 8. Sources

Competitors and pricing
- Playlister pricing: https://www.playlister.app/pricing
- Playlister story, founders, claims: https://www.playlister.app/why-we-made-it
- Playlister Lite: https://www.playlister.app/lite-product
- Playlister vs ProPresenter: https://www.playlister.app/propresenter-vs-playlister-try-free-today
- Playlister at Orange Conference: https://www.playlister.app/oc
- Playlister case study (Church on the Move): https://www.playlister.app/blog/how-church-on-the-move-streamlined-their-kids-ministry-workflow
- Playlister blog, Facebook group lists: https://www.playlister.app/blog/top-church-tech-facebook-groups and https://www.playlister.app/blog/top-kids-ministry-facebook-groups
- Playlister podcast: https://podcast.playlister.app/
- Playlister on faith.tools: https://faith.tools/app/824-playlister
- Playlister on G2 (blocked for me): https://www.g2.com/products/playlister/reviews ; Capterra: https://www.capterra.ca/software/185892/playlister ; Trustpilot: https://www.trustpilot.com/review/playlister.app
- Independent review of Playlister: https://learnofchrist.com/resources/playlister
- Yippee (competitor) vs Playlister: https://www.yippee.tv/blog/yippee-vs-playlister
- FreePlay: https://freeplay.church/ and https://support.churchapps.org/docs/freeplay/
- Amazing Life APlay: https://www.joinamazing.com/aplay and https://joinamazing.com/pricing
- ProPresenter: https://renewedvision.com/propresenter ; Capterra: https://www.capterra.com/p/170172/ProPresenter/
- Proclaim: https://logos.com/grow/affordable-pricing-for-churches-of-every-size ; Capterra: https://www.capterra.com/p/265496/Proclaim/pricing/
- Planning Center pricing: https://www.planningcenter.com/pricing ; help: https://help.planningcenter.com/en/planning-center-pricing.html ; integration: https://www.planningcenter.com/integrations/propresenter ; about: https://www.planningcenter.com/about
- Look Digital Signage (church page): https://lookdigitalsignage.com/church
- OptiSigns pricing: https://www.optisigns.com/pricing
- ScreenCloud pricing: https://www.screencloud.com/pricing
- Rise Vision comparison: https://www.risevision.com/blog/yodeck-vs-optisigns-vs-rise-vision/
- Kitcast roundup (self-interested): https://kitcast.tv/blog/best-digital-signage-software-for-churches
- DigitalSignage.com for churches: https://digitalsignage.com/_html/digital_signage_for_churches.html
- Amazon Signage Stick: https://www.sixteen-nine.net/2024/10/01/amazon-launches-100-signage-stick-and-small-digital-signage-cms-partner-roster/ ; https://www.netzwoche.ch/news/2026-10-16/amazon-lanciert-eigenes-digital-signage-display

Market size and trends
- Hartford/FACT 2020 and 2025 findings: https://goodfaithmedia.org/most-u-s-faith-communities-are-small-with-declining-attendance/ ; https://churchleaders.com/news/407585-congregational-attendance.html ; https://www.npr.org/2026/04/24/nx-s1-5791664/study-in-person-worship-attendance-in-u-s-rises-for-first-time-in-decades ; https://religionnews.com/2021/10/14/study-attendance-at-small-and-midsize-us-congregations-is-hemorrhaging/
- National Congregations Study (Duke): https://sites.duke.edu/ncsweb/files/2022/01/NCSIV_report_final.pdf ; https://today.duke.edu/2020/10/going-church-bring-your-smartphone ; https://baptistnews.com/article/another-major-study-confirms-most-american-congregations-are-small-but-most-churchgoers-attend-large-congregations/
- Australia (NCLS): https://www.ncls.org.au/articles/number-and-size-of-local-churches-in-australia/
- UK (BRIN / Brierley): https://www.brin.ac.uk/uk-church-statistics-2005-15/ ; https://www.brin.ac.uk/second-edition-of-uk-church-statistics/
- Canada: https://www.evangelicalfellowship.ca/evangelicalism ; https://faithtoday.ca/Magazines/2015-Sep-Oct/Why-Do-Evangelical-Churches-Do-Better-In-Today’s-C ; https://united-church.ca/sites/default/files/2025-10/united-church-of-canada-statistics-2024.docx
- Kids ministry (old Barna): https://thealabamabaptist.org/sunday-school-still-widely-embraced/ ; https://www.christiancentury.org/article/2005-08/slight-decrease-seen-sunday-school-classes
- Church technology surveys: https://pushpay.com/blog/introducing-the-state-of-church-technology-2025-report/ ; https://hub.pushpay.com/state-of-church-technology/ ; https://www.worshipfacility.com/2025/05/13/2025-state-of-church-tech-report-reveals-digital-tools-are-shaping-the-future-of-ministry/ ; https://exponential.org/ai-in-churches-2025-91-adoption-rate-reveals-dangerous-policy-gap/ ; https://churchtechtoday.com/2025-state-of-ai-in-the-church-national-survey-results-are-in/

Communities, media, events
- Facebook group lists: https://www.thecreativepastor.com/?p=8485 ; https://www.churchmotiongraphics.com/blog/were-better-together-join-the-visual-church-media-facebook-group/
- Kids ministry podcasts: https://ministry-to-children.com/the-best-childrens-ministry-podcasts/ ; https://www.playlister.app/blog/top-12-kids-ministry-podcasts ; https://podcast.feedspot.com/childrens_ministry_podcasts/
- ChurchTechToday: https://churchtechtoday.com/ ; Church Tech Today podcast: https://rephonic.com/podcasts/church-online-podcast ; Church Tech Weekly: https://audinate.com/press/church-tech-weekly-dante-networking-podcast
- Church tech YouTube channels: https://techie4christ.substack.com/p/five-youtube-channels-every-church
- r/churchtech reference: https://faithtools.substack.com/p/looking-for-an-online-community-of
- Conferences: https://churchtechtoday.com/fall-2026-church-conferences/ ; https://get.tithe.ly/blog/best-church-conferences ; https://theleadpastor.com/church-management/best-church-technology-conferences/ ; https://churchitnetwork.com/conference/2026

Church TV OS internal files read
- /Users/keithsparrow/Claude Code/Keith Personal/church-tv-os/HANDOFF.md, PROGRESS.md, APPS-PLAN.md, SLIDES-MODULE-PLAN.md, website/src/pages/*.html, website/README.md, store/AMAZON-SUBMISSION.md
