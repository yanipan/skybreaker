# Co-op release: store and policy changes

Draft, written 11/11. Nothing here is live. Apply when the first build with
co-op goes to the stores, not before: the privacy policy on GitHub Pages
describes the released app, and today it says the app has no camera access.

## 1. What's New text

```
CO-OP IS HERE
• Fly the whole run with a partner: PLAY NOW finds you a pilot, or invite a friend with a room code or QR
• Your own lives, money and upgrades. If you go down, your partner can fly in and rescue you
• One starbase for both: dock together, shop together
• Lose your connection? You have a minute to get back into the same run
• Also new: meteor showers, the mega asteroid, a ship that dodges your fire
```

## 2. Description (add near the top of the full description)

```
NEW: TWO-PLAYER CO-OP. Fight through all 24 sectors with a friend or a pilot found for you. Single-player is unchanged and your solo run is always kept.
```

Short description / subtitle idea (30 chars): `Space shooter, solo or co-op`

## 3. Privacy policy (docs/PRIVACY_POLICY.md and docs/privacy.html)

Add a section "Co-op":

> When you play co-op, your pilot name, your ship's position, what you shoot
> and your score are sent to our game server and shown to your partner for
> the length of that run. They are not stored after the run ends. Room codes
> expire after about 10 minutes. When no other player is available your
> partner may be a computer-controlled pilot.

Change "What the app does not do": remove "camera" from the list of things
never accessed.

Add to "Permissions the app requests":

> **Camera** (asked only when you tap SCAN QR CODE): used to read a friend's
> room code from their screen. Pictures are processed on your phone, are
> never saved and never leave it.

Decision for Yaniv before release: the last sentence of the co-op section
("may be a computer-controlled pilot"). Half of the AI partners are disguised
by design (the experiment). Saying it in the policy is the minimum I would
keep; hiding it completely is a store-review and trust risk.

## 4. Store forms

- **App Store, App Privacy**: no new data types. Pilot name and gameplay were
  already declared for the leaderboard (not linked to identity). Camera is
  used on the device only, so nothing to declare beyond the usage text in the
  build: "Scan a friend's QR code to join their co-op run." (already in
  `export_presets.cfg`).
- **Google Play, Data safety**: unchanged for the same reason. The build now
  asks for the CAMERA permission (`permissions/camera=true`); Play may ask
  why: "optional QR scan to join a friend's room, processed on device".
- **Age rating**: still no chat and no free text between players (pilot
  names only, already filtered). "Users interact" should be answered yes on
  both stores now (real-time play with other people).
- **App Review notes (Apple)**: the reviewer plays alone, so say: "Tap
  CO-OP > PLAY NOW. If no other player is online a computer pilot joins
  after about 10 seconds." This needs the lobby and room server to be
  reachable from Apple's network, so it depends on the cloud server.

## 5. Before any of this ships

- The lobby and room servers must be on a public server (`LobbyApi.PROD_URL`
  is still empty, so release builds do not show the CO-OP button at all).
- A phone test: camera scan, reconnect after backgrounding, feel over a real
  network.
- Push `master` so the invite page (`docs/join/`) is live at
  https://yanipan.github.io/skybreaker/join/ (the QR and COPY INVITE point there).
