# Claude Connectors Directory: listing text

Paste these into the portal at https://claude.ai/directory/manage (Submit new → MCP connector).

## 1. Connection

Server URL: https://gqkefjngblgomuovaivj.supabase.co/functions/v1/mcp
Users connect to different URLs: No (one URL for everyone)

## 3. Listing

**Server name**
Church TV OS

**One-liner** (max 200)
Run your church's TVs by asking Claude: schedule lobby signage, build kids-room playlists and Sunday slide decks, add songs from pasted lyrics, and control screens live.

**Description** (max 2,000)
Church TV OS runs the TVs around a church building: lobby and hallway signage, kids-room screens and auditorium slides. This connector lets church staff and volunteers manage all of it by asking Claude in plain words.

Signage: put one or more graphics on any screens for a time, a date range or every week ("show these two images every 10 seconds on the lobby TVs, weekdays 9 to 6"). Hold a single image for a whole slot, cancel what's scheduled, and see what's on each screen.

Kids: build playlists of videos, images, countdowns, lyrics, YouTube videos and live streams, then schedule them in rooms once or every week. Skip or swap a single Sunday.

Slides: build decks of text, media, songs and countdowns, and schedule or play them. Paste a song's lyrics and Claude adds it to the song library, split into verses and choruses, ready for a deck.

Live control: play something on a screen now, stop it, or show a short message.

Files: bring in graphics from Canva, Google Drive, Dropbox or any web link, or get an upload link to use on a phone or computer. Organise playlists and decks into folders and archive old ones.

Built for safety on a Sunday morning:
- Claude acts as the signed-in person, with exactly the access their role gives them. It can never do more than they can in the dashboard.
- Anything that changes what a screen shows, or removes something, is shown as a preview first. Nothing changes until the person says yes.
- Every change is logged and can be undone ("undo that").
- Claude warns before changing a room within 30 minutes of a service and won't remove schedules people made in the dashboard unless asked.
- What Claude creates goes into a "Made by assistant" folder so staff can see it at a glance.

Requires a Church TV OS account (app.churchtvos.com) with the Signage, Kids or Slides module.

**Categories** (1–5)
Productivity · Media · Communication
(choose the closest the portal offers; add "Nonprofit" or "Events" if listed)

**Documentation URL**
https://app.churchtvos.com/help/assistant.html

**Privacy policy URL**
https://app.churchtvos.com/privacy.html

**Support contact**
support@churchtvos.com

**Icon**
dashboard/public/app-icon.png (check it is at least 512×512 and square)

**URL slug** (permanent once published)
church-tv-os

## 4. Use cases

**Primary use cases**
1. Schedule signage graphics on church lobby and hallway TVs for an event, a date range or every week.
2. Build and schedule kids-room playlists (videos, countdowns, worship lyrics) for Sunday services.
3. Turn pasted song lyrics into a song library entry and a Sunday slide deck.
4. Check what's showing on each screen this weekend, and change or undo it.
5. Play something on a screen right now, or show a short message, during an event.

**What users need before connecting**
A Church TV OS account in a church (sign up free at app.churchtvos.com) with at least one of the Signage, Kids or Slides modules, and at least one TV paired to see content play. Their role in the church decides what Claude can do.

**Reads or writes data**
Both. It reads screens, rooms, schedules, playlists, decks, songs and media, and writes schedules, playlists, decks, songs, folders and uploaded media. Every write is previewed first and can be undone.

**Example prompts**
- "What's on the lobby TVs this Sunday?"
- "Show the Youth Night graphic on the Gym TV every Friday from 6:30 to 9:30pm."
- "Here are the lyrics to our new song. Add it with 2 lines per slide and make a Sunday deck with a welcome slide and a 5 minute countdown first."
- "Schedule the Week 1 kids playlist in the Kids Room every Sunday 9 to 12:30 until Christmas."
- "Undo the last change."

## 5. Company

Company name: Church TV OS (operated by Keith Sparrow, Ontario, Canada)
Website: https://app.churchtvos.com
Primary contact: Keith Sparrow, support@churchtvos.com

## 6. Authentication

Authentication requirement: Required
Method: OAuth 2.1 with dynamic client registration (Supabase Auth OAuth server). No client ID or secret needs to be entered; Claude registers itself.
Consent page: https://app.churchtvos.com/oauth/consent

## 7. Data handling

- Underlying API: our own (Church TV OS on Supabase). Not proxied from a third party.
- Personal health data: No.
- Sponsored content: No.
- Note for reviewers: we don't receive conversations. We store the OAuth grant, a log of changes the assistant makes (for undo), and files uploaded through it.

## 8. Test & launch

Test account instructions (paste, then add the password in the private field):

> Sign in at https://app.churchtvos.com with reviewer@churchtvos.com. The account is an admin of "Review Community Church", a sample church with four rooms (Auditorium, Lobby, Kids Room, Gym), five sample TVs, signage playlists and slots, a weekly Kids playlist, a weekly Sunday slide deck and three public-domain songs.
>
> To connect: add the server URL as a custom connector in Claude, choose Connect, sign in with the account above and press Approve.
>
> The TVs are sample screens with no physical device, so they show as offline: play_now, stop_playing and show_message will report that the screen hasn't connected. Every other tool works fully. Tools that change things return a preview first; call again with confirm=true to apply. undo_change reverses any change.
>
> Suggested first prompts: "List my screens", "What's scheduled this Sunday?", "Show the Coffee Bar graphic on the Lobby TV this Saturday 9am to noon", "Add this song" (paste any public-domain lyrics), "Undo that".

Confirm: every tool has been run as a custom connector in Claude.

## 9. Compliance

Seven acknowledgements. Read each one; nothing in the connector conflicts with them (no financial transactions, no AI media generation, no collection of conversation data).
