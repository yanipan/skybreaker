# Art still wanted for the 24-sector expansion (9/11/2026)

Everything below already works in the game on stand-ins (tinted copies of
existing hulls, recoloured copies of existing stills). Drop the real file in
at the path given and the stand-in disappears, no code change needed.
Workflow: paste one prompt into ChatGPT, save the grid, crop the cells
(Sharp / `sips`), strip the white background for sprites
(`scripts/tools/strip_backgrounds.gd`), save under the exact filename.

## 1. Two enemy sprites -> `assets/sprites/enemy_shade.png`, `assets/sprites/enemy_artillery.png`

> A 2x1 grid, exactly 2 cells, total image 2048x1024 pixels, each cell 1024x1024, thin white gutters, pure white background in every cell, no text, no labels. Top-down video-game spaceship sprites in the same style as a cel-shaded sticker illustration: bold dark outlines, flat saturated colours with simple two-tone shading, clean vector look, ship pointing straight up, centred in its cell, engine glow at the bottom. Cell 1: "SHADE" — a slim, angular phase-shifting interceptor, matte black hull with violet energy seams, semi-translucent purple ghost outline around it as if half out of phase, two thin forward dart cannons, violet engine flares. Cell 2: "ARTILLERY" — a broad, heavy siege gunship, brass and amber armour plates, one oversized central mortar barrel pointing up, side ammo drums, amber engine flares, squat and wide.

## 2. Two boss sprites -> `assets/sprites/boss6.png` (Null Archon), `assets/sprites/boss7.png` (The Herald)

> A 2x1 grid, exactly 2 cells, total image 2048x1024 pixels, each cell 1024x1024, thin white gutters, pure white background in every cell, no text. Top-down boss spaceship sprites for a vertical shoot-'em-up, matching a painterly comic style: dark metallic armour with heavy black outlines, glowing energy highlights, symmetrical design, facing down toward the viewer (guns pointing down), filling about 85% of the cell. Cell 1: "NULL ARCHON" — a cold machine-cathedral of black alloy and pale cyan light, a vertical central spire with a glowing cyan eye, six articulated cannon arms spread like a crown, cyan plasma vents. Cell 2: "THE HERALD" — a smaller splinter of a dark red titan: jagged crimson and violet armour, a single glowing violet core, forward-swept blade wings, trailing violet exhaust, menacing and fast-looking.

## 3. Three story stills -> `assets/cutscenes/cutscene_05_act5_01_empty_heart.png`, `..._02_skybreaker_rising.png`, `..._03_null_reach.png`

> A 3x1 grid, exactly 3 cells, total image 3072x1536 pixels, each cell 1024x1536 portrait, thin black gutters, no text, no captions, no letters anywhere. Dark cinematic sci-fi concept art, photoreal digital painting, deep blacks, volumetric light, a tiny lone pilot silhouette for scale where noted, consistent with a series about a vast ancient machine called the Skybreaker. Cell 1: inside an enormous hollow machine heart chamber, cables and ribs curving upward, the central cradle EMPTY and dark with faint dying cyan embers, the pilot standing alone on a ledge looking at the empty cradle. Cell 2: seen from behind a small fighter ship, a colossal dark red titan machine climbing up out of a shattered crystal planet into space, debris and dead ships streaming behind it like a tail, red light bleeding through cracks in its hull. Cell 3: the edge of known space, a last blinking beacon buoy in the foreground, beyond it pure starless black with a faint red glow far away, the small fighter ship flying toward the dark, cold cyan nebula wisps at the edges.
