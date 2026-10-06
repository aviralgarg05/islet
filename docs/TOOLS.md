# Tools

Pages you turn on when you want them: to-dos, a quick note, a unit converter, emoji, a camera mirror, a teleprompter, a stocks watchlist and today's sales. Each starts off. Turn one on in Settings → Tools and it appears in the page switcher's More menu (the "…" under the open island). Nothing about them shows in the closed island, and turning one off stops whatever it was doing.

Home can also show usage for more AI tools beside Claude Code and Codex: see [Usage limits](INTEGRATIONS.md#usage-limits).

The same Tools page also turns on a Shortcuts page, a Weather page and a System page (CPU and memory, measured only while it is open). Lyrics, the month calendar, the stopwatch and focus sounds are switched on from the Settings page of the feature they belong to (Now Playing, Calendar & Reminders, Timers).

## Arranging the pages

Settings → General → Island pages lists the pages that are on, in the order the switcher shows them: up to four in the capsule under the island, the rest in its More menu.

- Drag a page onto another to put it there, or onto **In the capsule** or **Under More**. Each row's "…" menu moves it up, down, or between the two, for the keyboard.
- A page's switch leaves it out of the switcher without turning its feature off. A page opened another way (a file dropped on the island, a shortcut, the API) still shows while it is open.
- Home is always in the capsule. With more than four pages there, the last one goes under More. The More menu stays even with no page under it, for Keep awake, Keep open, Settings, Send feedback and Quit.
- A page whose feature is off keeps its place for when it comes back on. **Reset** goes back to Home, Today and Shelf in the capsule.

`config.json`: `"islandPages": {"bar": ["home", "todos", "today", "shelf"], "more": ["clipboard", "weather"], "hidden": ["widgets"]}`. Pages left out of both lists go at the end of the one they come in.

## To-dos

Add a line, star what matters, tick it off.

- Type in **Add a to-do** and press Return. What is left to do comes first, starred lines at the top, then the newest; what is done goes to the end, struck through, until **Clear done**.
- Hover a line for its star and ×; the right-click menu ticks it off, stars it, copies it or removes it.
- The list is kept in `todos.json` in Casement's support folder, readable only by you (up to 200 lines). A file that can't be read is set aside as `todos.json.corrupt`, never written over.

`config.json`: `"todosEnabled": true`.

## Quick note

A scratch pad that keeps its text.

- Click the page and type. The note is saved half a second after you stop typing, and when the page or the island closes, in `note.txt` in Casement's support folder (readable only by you, up to 100,000 characters). An empty note removes the file.
- Before you click into it, the right-click menu copies or clears the note; while you type, it is the usual cut, copy and paste. Under the pointer it shows how many words it has.

`config.json`: `"noteEnabled": true`.

## Unit converter

Type an amount and a unit, and read the answer: `5 ft in cm`, `70 kg to lb`, `100 °F in °C`, `2 cups = ml`, `60 mph in km/h`.

- Lengths, weights, temperatures, volumes and speeds, from millimetres to nautical miles and teaspoons to cubic metres. Imperial and US units use their exact definitions, so a tablespoon is 3 teaspoons to the last digit.
- With no unit to convert to, the usual ones answer (`5 ft` gives metres and centimetres).
- A plain pint, gallon or fluid ounce is the British one when the Mac's region is the United Kingdom and the US one otherwise; `us gallon` or `uk pint` says which outright.
- Click an answer, or press Return, to copy its number, without thousands separators so it pastes into a sum or a form. Numbers are shown the way your region writes them, to six significant figures, and a long whole number in full.
- While the converter is on, the Ask box answers a conversion as you type it, in place of its hint.

Everything is worked out on the Mac. `config.json`: `"converterEnabled": true`.

## Emoji

Find any emoji by name or by the words people use for it ("lol", "tada", "thumbs up", "flag japan"), and click it to copy it.

- With nothing typed, the ones you used lately come first, then the everyday ones, then the rest, faces first and flags last.
- Every emoji macOS can name is there, from the system's own Unicode tables, with the flag of every region and the commonest sequences (people at work, families, the rainbow flag). Nothing is downloaded.
- **Type emoji where you're typing** (off by default) types the emoji into the app you were typing in instead of copying it. It needs Accessibility, which macOS asks for when you switch it on; without it the emoji is copied. Casement sends that one character, only when you click an emoji, and reads nothing.
- The emoji you used lately are kept in `emoji.json` in Casement's support folder (at most 24).

`config.json`: `"emojiEnabled": true, "emojiTypes": false`.

## Camera mirror

Your camera, centred under the notch where the lens is, for a quick look before a call.

- The camera runs only while the Mirror page is open. Switch page or close the island and it stops, so the camera light is on exactly while you can see yourself. It also stops while the screen is locked or asleep, even with the page left open, and comes back once you unlock.
- Nothing is recorded, kept or sent: the picture goes straight to the screen.
- **Flip like a mirror** (on by default) shows you as a mirror does. A video call shows other people the unflipped picture.
- The first time, the page offers **Allow camera** and macOS asks. If you said no, the page and Settings → Permissions open Privacy & Security → Camera.

`config.json`: `"mirror": {"enabled": true, "flipped": true}`.

## Teleprompter

Your script moves up just under the camera, so you read it while looking into the lens.

- Write or paste the script in Settings → Tools → Teleprompter, or press **Paste** on the empty page. It is saved as you type, in `teleprompter.txt` in Casement's support folder (readable only by you).
- Press play on the page. **+** and **−** change the pace by 10 words a minute (60 to 300, 140 to start). Settings shows how long the script takes at that pace.
- Scroll up or down over the script to move it by hand; that pauses it. A sideways swipe, or any swipe on the empty page, works as it does elsewhere. At the end, play starts again from the top. The page's menu has **Back to the top**.
- **See-through while reading** turns the open island to clear glass on this page, whatever the theme.
- **Text size** goes from 14 to 40 points.

Nothing runs on a timer while the script plays.

`config.json`: `"teleprompter": {"enabled": true, "wordsPerMinute": 140, "textSize": 20, "seeThrough": false}`.

## Stocks

A watchlist with each price, the day's change and a line for the day, with the previous close as a dotted line.

- Add up to 12 symbols in Settings → Tools → Stocks: shares (`AAPL`), indices (`^GSPC`, `^FTSE`), currencies (`EURUSD=X`) or crypto (`BTC-USD`).
- Prices come from Yahoo Finance's public chart data, with no account or key. They may be delayed.
- Casement asks only while the Stocks page is open: when it opens (if the prices are more than a minute old), then every two minutes until you leave it. Each symbol is one request to `query1.finance.yahoo.com`.
- A row says **Not found** only for a symbol Yahoo doesn't know. Without a connection it says **Can't connect**, and a price from earlier stays until a new one arrives.

`config.json`: `"stocks": {"enabled": true, "symbols": ["AAPL", "MSFT", "^GSPC"]}`.

## Sales

Today's takings from your stores: one total, large, and each store beside it, with the number of orders.

| Store | Key to paste | What counts |
|---|---|---|
| Stripe | A restricted key with Read on Charges | Paid charges, less refunds |
| Shopify | A custom app's Admin API access token with read access to orders, and the store's address | Orders not cancelled or test, at their current total |
| Lemon Squeezy | An API key (these can't be limited to reading; Casement only reads) | Paid and partly refunded orders, less refunds, not test mode |
| Gumroad | An application's access token | Sales not refunded, charged back or disputed |
| Dodo Payments | An API key | Succeeded payments not fully refunded |
| Polar | An organisation token that can read orders | Paid and partly refunded orders, less refunds |
| Paddle | An API key that can read transactions (live or sandbox) | Completed transactions |

- **Connect…** checks the key by asking the store for today's sales, then keeps it in your Keychain. Settings shows only that a store is connected; **Remove** deletes the key.
- "Today" is since midnight on your Mac. The total leads with your own currency when there are takings in it; other currencies show beside it.
- Casement asks each connected store when the Sales page opens (if the figures are more than a minute old) and every 15 minutes while Sales is on and the Mac is unlocked, and again at midnight so "Today" starts afresh. It doesn't ask while the screen is locked or in Low Power Mode, and picks up again when you unlock or Low Power Mode ends.
- Requests go only to that store's API (`api.stripe.com`, your `*.myshopify.com`, `api.lemonsqueezy.com`, `api.gumroad.com`, `live.dodopayments.com`, `api.polar.sh`, `api.paddle.com`), over HTTPS, with no cookies, and never follow a redirect.
- A store that turns a key down shows a warning on the page and in Settings, and the total leaves it out.

`config.json`: `"sales": {"enabled": true, "stores": ["stripe", "shopify"], "shopifyStore": "example.myshopify.com"}`. Keys are never in this file.
