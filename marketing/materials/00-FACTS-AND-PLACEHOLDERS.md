# Facts, claims and placeholders (read before using anything)

Every file in this folder follows this sheet. If a fact here changes, search the folder for the old wording.
Checked against the code and store kits on 2026-10-23: `PROGRESS.md`, `HANDOFF.md`, `APPS-PLAN.md`, `store/AMAZON-SUBMISSION.md`, `store/GOOGLE-PLAY-SUBMISSION.md`, `roku-app/README.md`, `website/src/pages/*`, `marketing/01-market-research.md`, `marketing/03-marketing-strategy.md`.

## Safe to say (built and in the code)

| Claim | Where it comes from |
|---|---|
| TV app live on Fire TV, Google TV and Roku. LG and Samsung coming soon. | Launch status given by Keith. **Confirm each store is genuinely live and swap in the real store links before sending anything.** |
| Three modules: Kids, Signage, Slides. | website features page, dashboard |
| Pair a TV with a six-character code, then pick the room in the dashboard. | store kits, `PairPage.tsx` |
| Manage everything from the web dashboard at app.churchtvos.com, and it works on a phone. | website, store kits |
| Run a room from your phone: next, back, jump to a slide, blank, play now, send a message (200 characters), see which screens are online. This is the dashboard's Control page in a phone browser. | `dashboard/src/control`, website features |
| One TV can switch modules on a schedule (Signage on weekdays, Kids on Sunday). | HANDOFF, store kits |
| Operator role can run the remote but cannot edit anything. Roles: owner, admin, editor, operator, limited by module and campus. | website, `APPS-PLAN.md` |
| Plays from saved content if the internet drops. TVs download what is scheduled ahead of time. | website, store kits |
| Landscape or portrait per screen. | store kits |
| Songs library with lyrics split into slides and a play order. PDF, PowerPoint and picture import. Themes and backgrounds. Countdowns. YouTube in Kids playlists. | website, `PROGRESS.md` |
| Your logo and colours on the TV. | store kits |
| Free trial for every new church: Kids + Signage, 2 TVs (server migration 2026-10-20). | `AMAZON-SUBMISSION.md` section 8 |
| No ads, no analytics SDKs in the TV app. Demo mode needs no account. | store kits |
| Church uploads and licenses its own content. | strategy 03, section 10 |

## Say carefully (true, but with a limit that belongs in the copy)

- **Roku:** the channel is new. It has never been tested broadly. YouTube items are not supported on Roku, and video and live streams are skipped on portrait screens (`roku-app/README.md`). Never say "everything works the same on Roku".
- **Fire TV:** newer Fire TV sticks that run Amazon's Vega OS cannot run it. Auto-launch on power-on is a Fire TV option only (it is not available on Google TV).
- **Google TV:** no Menu button on the remote, so Settings and demo are reached from a button on the pairing screen or by holding OK.
- **YouTube** slides do not rotate on portrait screens.
- **PowerPoint import** turns slides into editable text slides and keeps pictures. Animations are not carried over. For the exact look, export to PDF first.
- **Trial length, number of TVs in trial, and any price:** placeholders only.
- **"Built at Forward Church":** fine as a founder story. Do not use Forward Church's name, logo or brand as an endorsement until the written note from church leadership exists (HANDOFF open item). Church TV OS is Keith's, Forward Church is customer #1.

## Do NOT claim or promote

- **iPhone, iPad and Mac apps.** They exist in the repo but are not shipped (APPS-PLAN.md is planning; the website calls them beta). Marketing says "run it from your phone" because the web dashboard remote works in a phone browser. Where the apps are mentioned at all, the only wording is "iPhone and Mac apps: coming soon".
- **Planning Center, CCLI, Orange or any curriculum integration.** None exist.
- **NDI.** Experimental. Not promoted anywhere.
- **Any price, discount or "free forever".** Pricing is not decided. Use `[PRICE]`.
- **Customer counts, ratings, logos, testimonials, "trusted by".** None exist. Use `[TESTIMONIAL]`.
- **Competitor names** in any public copy, ads, store listings or keywords. Playlister is never named. Category phrases are used instead ("Apple TV based kids tools", "free open source kids players", "signage only tools"). Named comparisons live only in `09-sales/comparison-sheet.md` appendix B, which is marked **internal, do not publish**.
- **"Replaces ProPresenter".** It does not. Slides is for rooms, chapels, overflow, satellites and secondary screens.
- **Photos or video of identifiable children.** Screens only.
- **Copyrighted songs, curriculum or backgrounds** in any demo asset. All graphics here use the built-in demo screens only.

## Voice rules used in every file

Keith's voice: warm, direct, practical. Open on a concrete moment. Ellipses instead of dashes. Self-deprecating where it is honest. No "revolutionize", "transform your ministry", "AI-powered", "game-changer", no fear-of-falling-behind. Say what it does ("keeps your screens running"), not what it will do to a church's soul. CSB for any Scripture. No doctrinal statements are made anywhere in this folder, so the statement-of-faith skill was not needed.

## Placeholders (find and replace before use)

| Placeholder | Meaning | Decide by |
|---|---|---|
| `[PRICE]`, `[PRICE PER TV]`, `[PRICE KIDS]` etc. | Pricing is not decided. Never publish one. | 2026-12-04 (strategy 03) |
| `[TRIAL DAYS]` | Trial length (strategy suggests 30; extending for beta churches). | with pricing |
| `[LAUNCH DATE]` | Strategy assumes Tuesday 2027-01-26. This folder was written as "it is live". | now |
| `[FIRE TV STORE LINK]`, `[GOOGLE TV STORE LINK]`, `[ROKU STORE LINK]` | Real store URLs. | when approved |
| `[FOUNDING OFFER]`, `[FOUNDING SPOTS]` | What the founding churches get and how many (strategy suggests 50). | with pricing |
| `[TESTIMONIAL]`, `[QUOTE NAME, ROLE, CHURCH]` | Real quote with written permission only. | after beta |
| `[N ROOMS]`, `[N TVS]`, `[N SUNDAYS]` | Real Forward Church numbers, dated. | before case study |
| `[POSTAL ADDRESS]` | A real mailing address for CASL / CAN-SPAM footers. | before first send |
| `[UNSUBSCRIBE LINK]` | Provided by the email tool. | when tool chosen |
| `[YOUTUBE LINK]`, `[DEMO VIDEO LINK]` | After videos exist. | after recording |
| `[WAITLIST LINK]` | Waitlist form (needs an unticked consent box). | now |
| `[PHONE OR BOOKING LINK]` | Optional demo booking page. | optional |
