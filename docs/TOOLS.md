# Tools

Four pages you turn on when you want them: a camera mirror, a teleprompter, a stocks watchlist and today's sales. Each starts off. Turn one on in Settings → Tools and it appears in the page switcher's More menu (the "…" under the open island). Nothing about them shows in the closed island, and turning one off stops whatever it was doing.

Home can also show usage for more AI tools beside Claude Code and Codex: see [Usage limits](INTEGRATIONS.md#usage-limits).

## Camera mirror

Your camera, centred under the notch where the lens is, for a quick look before a call.

- The camera runs only while the Mirror page is open. Switch page or close the island and it stops, so the camera light is on exactly while you can see yourself. It also stops while the screen is locked or asleep, even with the page left open, and comes back once you unlock.
- Nothing is recorded, kept or sent: the picture goes straight to the screen.
- **Flip like a mirror** (on by default) shows you as a mirror does. A video call shows other people the unflipped picture.
- The first time, the page offers **Allow camera** and macOS asks. If you said no, the page and Settings → Permissions open Privacy & Security → Camera.

`config.json`: `"mirror": {"enabled": true, "flipped": true}`.

## Teleprompter

Your script moves up just under the camera, so you read it while looking into the lens.

- Write or paste the script in Settings → Tools → Teleprompter, or press **Paste** on the empty page. It is saved as you type, in `teleprompter.txt` in Islet's support folder (readable only by you).
- Press play on the page. **+** and **−** change the pace by 10 words a minute (60 to 300, 140 to start). Settings shows how long the script takes at that pace.
- Scroll up or down over the script to move it by hand; that pauses it. A sideways swipe, or any swipe on the empty page, works as it does elsewhere. At the end, play starts again from the top. The page's menu has **Back to the top**.
- **See-through while reading** turns the open island to clear glass on this page, whatever the theme.
- **Text size** goes from 14 to 40 points.

The script moves with one linear animation from where it is to the end, and Islet's one deadline timer marks the end, so nothing ticks while it plays.

`config.json`: `"teleprompter": {"enabled": true, "wordsPerMinute": 140, "textSize": 20, "seeThrough": false}`.

## Stocks

A watchlist with each price, the day's change and a line for the day, with the previous close as a dotted line.

- Add up to 12 symbols in Settings → Tools → Stocks: shares (`AAPL`), indices (`^GSPC`, `^FTSE`), currencies (`EURUSD=X`) or crypto (`BTC-USD`).
- Prices come from Yahoo Finance's public chart data, with no account or key. They may be delayed.
- Islet asks only while the Stocks page is open: when it opens (if the prices are more than a minute old), then every two minutes until you leave it. Each symbol is one request to `query1.finance.yahoo.com`.
- A row says **Not found** only for a symbol Yahoo doesn't know. Without a connection it says **Can't connect**, and a price from earlier stays until a new one arrives.

`config.json`: `"stocks": {"enabled": true, "symbols": ["AAPL", "MSFT", "^GSPC"]}`.

## Sales

Today's takings from your stores: one total, large, and each store beside it, with the number of orders.

| Store | Key to paste | What counts |
|---|---|---|
| Stripe | A restricted key with Read on Charges | Paid charges, less refunds |
| Shopify | A custom app's Admin API access token with read access to orders, and the store's address | Orders not cancelled or test, at their current total |
| Lemon Squeezy | An API key (these can't be limited to reading; Islet only reads) | Paid and partly refunded orders, less refunds, not test mode |
| Gumroad | An application's access token | Sales not refunded, charged back or disputed |
| Dodo Payments | An API key | Succeeded payments not fully refunded |
| Polar | An organisation token that can read orders | Paid and partly refunded orders, less refunds |
| Paddle | An API key that can read transactions (live or sandbox) | Completed transactions |

- **Connect…** checks the key by asking the store for today's sales, then keeps it in your Keychain. Settings shows only that a store is connected; **Remove** deletes the key.
- "Today" is since midnight on your Mac. The total leads with your own currency when there are takings in it; other currencies show beside it.
- Islet asks each connected store when the Sales page opens (if the figures are more than a minute old) and every 15 minutes while Sales is on and the Mac is unlocked, and again at midnight so "Today" starts afresh. It doesn't ask while the screen is locked or in Low Power Mode, and picks up again when you unlock or Low Power Mode ends.
- Requests go only to that store's API (`api.stripe.com`, your `*.myshopify.com`, `api.lemonsqueezy.com`, `api.gumroad.com`, `live.dodopayments.com`, `api.polar.sh`, `api.paddle.com`), over HTTPS, with no cookies, and never follow a redirect. At most ten pages are read per store each time (Paddle sends 30 transactions a page, the others 100), and a reply over 8 MB is dropped as it arrives.
- A store that turns a key down shows a warning on the page and in Settings, and the total leaves it out.

`config.json`: `"sales": {"enabled": true, "stores": ["stripe", "shopify"], "shopifyStore": "example.myshopify.com"}`. Keys are never in this file.
