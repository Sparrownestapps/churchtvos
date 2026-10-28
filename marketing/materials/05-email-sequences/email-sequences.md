# Email sequences

Five sequences, written to be loaded into an email tool with double opt-in. Plain-text style, from Keith, replies go to a real inbox. Nothing here has been loaded or sent.

**Shared rules**
* From: Keith Sparrow <support@churchtvos.com> (or the address the tool uses; replies must reach you).
* Every marketing email gets the **standard footer** below. Sequences 2 to 3 go to people who created an account (an existing business relationship). Purely "how do I use it" messages are service messages, but anything promoting a plan, offer or referral is a commercial message and needs the footer and an unsubscribe. When in doubt, include them. Confirm with CRTC guidance or a lawyer.
* Merge fields: `{{first_name}}`, `{{church_name}}`, `{{platform}}`. If a field is blank, the fallback is "there" (Hi there,).
* Send times: Tuesday to Thursday, mornings. Avoid 20 December to 1 January. Never send on a Sunday.
* UTM: `utm_source=email&utm_medium=email&utm_campaign=[campaign]&utm_content=[email id]`.
* Every email asks at most one thing.
* Pricing, trial length, founding offer, referral reward: placeholders until decided.

**Standard footer**
> You're receiving this because [REASON: "you joined the Church TV OS waitlist on {{date}}" / "you started a Church TV OS trial on {{date}}"].
> Church TV OS · Keith Sparrow · [POSTAL ADDRESS] · support@churchtvos.com
> [Unsubscribe]([UNSUBSCRIBE LINK]) · [Privacy](https://app.churchtvos.com/privacy.html)

---

# 1. Waitlist nurture (pre-launch and LG/Samsung list)

Goal: keep warm people warm, learn what they run today, get them to start a trial the day it's live. Send weekly in the last 6 weeks before launch; for the LG/Samsung list send a "why you're here" note, then one email per milestone.

### W0: Welcome (immediately after double opt-in)
**Subject:** You're on the list. One question.
Hi {{first_name}},

Thanks for joining the Church TV OS list. You told me you're interested in {{platform}}. I'll email you when it's ready on that TV, and not much in between.

One question, and replies go straight to me: **what do you run on your TVs today?** A laptop and HDMI? A USB stick? Something else? I read every answer, and it shapes what I build.

Keith

### W1 (about 5 weeks before launch): What I'm building
**Subject:** Here's what Church TV OS actually is
Hi {{first_name}},

Short version: it puts your kids rooms, lobby screens and Sunday slides on TVs you already own, and you run them from your phone.

Three modules (Kids, Signage, Slides), one six-character pairing code per TV, and a web dashboard that works on a phone.

Here's the 90-second look: [DEMO VIDEO LINK].

If you're only interested in one of the three, tell me which. That helps me.

Keith

### W2: Setup preview
**Subject:** Pairing a TV takes about a minute
Hi {{first_name}},

I recorded the setup so you can see how little there is to it: open the app, read the code, type it into the dashboard, pick the room. [3-minute video: LINK]

If you've got a spare Fire stick, Google TV box or Roku, you'll be able to try it the day it's live.

Keith

### W3: The Sunday question
**Subject:** What happens when the Wi-Fi drops?
Hi {{first_name}},

It's the first thing most tech directors ask me. TVs download what's scheduled ahead of time, so the room keeps playing from saved content, and it catches up when the connection returns.

What I can't promise: a message you push from your phone needs the internet to arrive. I'd rather tell you that now.

Anything else you're nervous about on a Sunday? Reply, and I'll answer it in the next email.

Keith

### W4: Honest status
**Subject:** Where things stand (and where they don't)
Hi {{first_name}},

Here's the honest status for {{platform}}: [REAL STATUS: "in store review", "in testing", "live"]. LG and Samsung: [REAL STATUS]. I'm not going to give you a date I don't control.

If you'd like to try it on a different TV in the meantime, a Fire TV, Google TV or Roku device in an HDMI port works on almost any screen.

Keith

### W5: Founding-church note
**Subject:** A founding-church offer, and why it's capped
Hi {{first_name}},

[FOUNDING OFFER and FOUNDING SPOTS.] The first [FOUNDING SPOTS] churches get [OFFER], and a say in what I build next. It's capped on purpose: I want to answer every founding church personally. Closes [DEADLINE].

If that's you, here's how to claim it: [LINK].

Keith

### W6 (launch day): see `../01-launch/launch-email.md`.

### W7 (3 days after launch, to non-clickers)
**Subject:** Did the app show up for you?
Hi {{first_name}},

Quick check. Church TV OS has been live for a few days. If you haven't had a chance to try it, here's the 3-minute version: [VIDEO]. If something got in the way, reply and tell me, I'll help.

Keith

---

# 2. Trial onboarding (account created)

Goal: get a TV paired and used on a Sunday within 14 days. This is the metric that matters. Days are from account creation. If the trial is longer or shorter than `[TRIAL DAYS]`, shift the later emails.

### T0: Welcome (immediately)
**Subject:** Welcome. Let's get your first TV on.
Hi {{first_name}},

You're in. Here's the order I'd do things in, and you can stop after step 2 and still see it working:

1. Install Church TV OS on a TV: [Fire TV](LINK) · [Google TV](LINK) · [Roku](LINK).
2. Pair it: open the app, read the six-character code, type it into Screens, Pair a TV.
3. Put a sign on it (Signage → New sign).

No TV to hand? Open the app's demo mode, no account needed.

Reply if anything gets stuck. It's me.
Keith

### T1: Pair a TV
**Subject:** Pair your first TV (60-second video)
Hi {{first_name}},

If your TV isn't paired yet, this is the one thing to do: [60-second pairing video: LINK].

Three snags people hit: the code needs to be typed exactly as shown; the TV has to be online the first time; and newer Fire TV sticks running Amazon's Vega OS can't run the app. If yours is one of those, reply and I'll suggest options.

Keith

### T3: First room
**Subject:** Schedule your first kids room
Hi {{first_name}},

Here's the Thursday habit in three steps: make a playlist (a countdown, a video, lyrics), schedule it for the room, check the screen status from your phone.

[Tutorial 2: LINK]

Keith

### T7: Give it to a volunteer
**Subject:** Hand the remote to someone else
Hi {{first_name}},

The real test of a Sunday system is whether a volunteer can run it. Invite someone as an **operator** (People → Invite). They can step through slides, blank the screen and send a message. They can't edit anything.

Try a test run with them this week: [volunteer checklist PDF: LINK, to be written].

Keith

### T10: What if the internet drops?
**Subject:** The Sunday Wi-Fi test
Hi {{first_name}},

Before you rely on it, try this once: schedule something, let the TV download it, then turn off the router for a minute. It should keep playing from saved content. If it doesn't, tell me which device and I'll look into it.

Keith

### T14: Check-in
**Subject:** How's it going?
Hi {{first_name}},

Two weeks in. Have you run a room on a Sunday yet? [Yes → "Tell me what went well and what didn't."] [No → "What got in the way? I'll help you get there."] Just hit reply.

Keith

### T-5: see Sequence 3.

---

# 3. Trial ending

Send at T-7, T-3 and T-0 (relative to the end of `[TRIAL DAYS]`) and one day after. If the church has not paired a TV by T-7, send the "extend" variant. **Never** pressure; give a real way to say no.

### E1 (T-7): What you've done and what's next
**Subject:** Your Church TV OS trial ends in a week
Hi {{first_name}},

Your trial ends on {{end_date}}. So far you've {{paired_tvs}} TV(s) paired and {{items}} things scheduled. [If zero: "You haven't paired a TV yet, which is fine, it's the part where most people need a hand."]

After the trial, pricing is per module and per TV: [PRICE]. [FOUNDING OFFER, if still open.] Nothing is charged unless you choose a plan: [PLAN LINK].

Would more time help? Reply and I'll extend you.

Keith

### E1b (T-7, no TV paired): extend
**Subject:** Need more time? You've got it.
Hi {{first_name}},

I noticed no TV has paired yet. Most churches that get stuck at this point are one small thing away. Reply with what you're using, and I'll sort it out with you. Your trial can be extended while we do. [CONFIRM you really will extend.]

Keith

### E2 (T-3): Decision helper
**Subject:** Which modules do you actually need?
Hi {{first_name}},

You don't have to take all three. Many churches start with one: Kids for the rooms, Signage for the lobby, Slides for a chapel. Pick what earns its place. [PRICE per module and TV.]

Not sure? Tell me what you run and I'll tell you what I'd choose.

Keith

### E3 (T-0): Last day
**Subject:** Your trial ends today
Hi {{first_name}},

Today's the last day. [If paid: "Your plan starts tomorrow."] [If not: "After today your screens will go to a plain 'plan needed' message, and your content stays safe for [GRACE PERIOD]. CONFIRM what really happens before sending."]

Choose a plan: [LINK]. Or tell me why not. A one-line reply is a gift to me.

Keith

### E4 (T+1): Not now?
**Subject:** No hard feelings
Hi {{first_name}},

If Church TV OS wasn't the right fit, I'd genuinely like to know why: price, a missing thing, the TV, timing. One line is plenty. Your content stays safe for [GRACE PERIOD] if you change your mind.

Thanks for trying it.

Keith

---

# 4. Founding-church offer (to waitlist and trial users)

Rules: say how many spots exist, say what the deal is, say what it costs *you*, and do not pretend scarcity. Only show a spots-left number if it's true that day.

### F1: The offer
**Subject:** Founding churches: [FOUNDING SPOTS] spots
Hi {{first_name}},

I'm opening [FOUNDING SPOTS] founding-church places for Church TV OS.

**What you get:** [FOUNDING OFFER: for example a locked price for [N] months, a direct line to me, a vote on what I build next (LG and Samsung timing, other integrations). Only list what you will actually deliver.]
**What I ask:** use it for real, tell me what's wrong, and if you're happy, [consent to a short quote and name, written permission only].

It closes on [DEADLINE] or when the places are gone.

[CLAIM A PLACE](LINK)

Keith

### F2 (3 days later, to openers)
**Subject:** What founding churches are asking me for
Hi {{first_name}},

Here's what the first few asked for: [REAL requests only. If none yet, send a different email.] If you've got something on your wish list, claim a place and tell me.

Keith

### F3 (2 days before close)
**Subject:** Founding places close [DAY]
Hi {{first_name}},

[N] places are left `[ONLY IF TRUE]`. After [DEADLINE] the founding terms close for good. No pressure. If it isn't right, it isn't right.

[LINK]

Keith

### F4 (after close, to those who didn't claim)
**Subject:** Founding places are closed. Here's what's next.
Hi {{first_name}},

The founding places are full. You're still welcome to try it free: [LINK]. I'll keep you posted when we add things.

Keith

---

# 5. Referral

Programme text is in `../10-outreach/referral-programme.md`. Reward terms are placeholders. Principle from strategy 03: "Give a month, get a month", no cash, no per-sign-up rewards that tempt fake accounts, and reward only after the referred church pairs a TV and stays 30 days.

### R1 (day 30 after purchase, to paying churches)
**Subject:** Know a church that would use this?
Hi {{first_name}},

If Church TV OS is helping at {{church_name}}, you probably know another church whose Sunday could use it. Here's your link: [REFERRAL LINK].

When they pair a TV and stay 30 days, you get [REWARD: a free month] and they get [REWARD: extra trial days]. Terms: [LINK].

No pressure. Thank you for being one of the first.

Keith

### R2 (day 60, to people who haven't referred)
**Subject:** One easy way to help another church
Hi {{first_name}},

Rather than a link, here's a text you can forward: "We use Church TV OS for our [kids rooms / lobby]. It runs on a Fire stick and I run it from my phone. Worth a look: [LINK]". Copy, paste, done.

Keith

### R3 (to a referred church, welcome)
**Subject:** {{referrer_church}} thought you'd like this
Hi {{first_name}},

{{referrer_name}} at {{referrer_church}} suggested you try Church TV OS. You have [EXTRA TRIAL DAYS] extra trial days on top of the usual. Start here: [LINK].

Keith

### R4 (reward earned, to the referrer)
**Subject:** You've earned [REWARD]
Hi {{first_name}},

{{referred_church}} paired a TV and has been running for 30 days. [REWARD] is on your account. Thank you.

Keith

### Post-purchase and win-back (from strategy 03, optional)
* Day 7 after purchase: "How did your first paid Sunday go?" Day 30: review ask, **no incentive**: "If it's helped, a short honest review in the store helps other churches find it. If not, tell me instead." Day 60: "What would you build next?"
* Win-back day 45 and 90 after cancellation: one short, guilt-free note: "Anything I should know? Your content is [still here / gone on DATE]."
