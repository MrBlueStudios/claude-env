# trading-free-data

**Question:** Which market-data sources can feed a trading bot for free, with history for backtesting and a live stream, and where do the free tiers end?

**Answer:** For crypto, exchange public APIs are the only genuinely free live source: Binance's REST and WebSocket need no account for market data, allow 1,200 requests a minute, and go back years; use CCXT (MIT) so the exchange can change. For aggregated or cross-exchange data, CoinGecko's Demo key gives 10,000 calls a month with a year of hourly history, REST only. For US stocks, Alpaca's Basic plan is free with IEX-only quotes, 200 requests a minute, 30 streamed symbols, history since 2016 and the latest 15 minutes withheld; yfinance works for research but should not be in the loop of a running bot.

**Confidence:** medium — Alpaca's and CoinGecko's limits are from their own pages; Binance's are from secondary comparisons and should be read off Binance's API documentation before the bot depends on them.

**What would change our decision:**
- A bot that polls every minute: one such bot alone uses about 43,000 calls a month, so any monthly-capped API (CoinGecko Demo, Twelve Data) is out and only exchange streams or Alpaca's uncapped plan fit.
- Trading non-US stocks or needing the consolidated tape: Alpaca's free tier does not cover it, and every stock alternative found costs from about $9 a month.

## Findings

1. **Binance public market data.** REST plus WebSocket, no key needed for market data, 1,200 request-weight a minute, full candle history, with the caveat that it covers Binance-listed pairs only and degrades in volatile moments. EU users trade through Binance's EU entity; market data is the same. Source: [Binance API comparison in a quant data guide](https://waylandz.com/quant-book-en/Data-Sources-and-API-Comparison/) — secondary; the 1,200 figure is UNVERIFIED against Binance's own docs.

2. **CCXT** (MIT, 44.9k stars, pushed 2026-11-15) unifies REST access to 100+ exchanges; CCXT Pro, the WebSocket layer, is a paid product. For a free stream, use the exchange's own WebSocket directly. Source: GitHub API; [CCXT README](https://github.com/ccxt/ccxt).

3. **CoinGecko Demo:** keyless public endpoints with unspecified shared limits, or a free Demo key with 10,000 calls a month, 100 a minute, OHLCV and one year of daily and hourly history. WebSocket is paid (from the $35 plan). Good for metadata, rankings and sanity checks, not for the trading loop. Source: [CoinGecko: best free crypto API](https://www.coingecko.com/learn/best-free-crypto-api) (vendor), [CoinGecko API pricing](https://www.coingecko.com/en/api/pricing).

4. **Alpaca Basic (US stocks):** free; IEX feed only; 200 API calls a minute; WebSocket limited to 30 symbols; history since 2016; the latest 15 minutes of historical bars withheld; no daily cap. Algo Trader Plus ($99 a month) lifts to all exchanges and 10,000 a minute. Paper trading is free. Source: [Alpaca: About Market Data API](https://docs.alpaca.markets/docs/about-market-data-api) (official).

5. **yfinance:** unofficial Yahoo scraping; unpublished and shifting limits, sessions that expire, no SLA. Fine for a notebook, wrong for a bot. Source: [Alphanume comparison](https://www.alphanume.com/blog/best-free-stock-market-apis-what-you-actually-get-and-what-you-dont) — secondary.

6. **Bulk history for backtesting is CSV, not API.** CryptoDataDownload and Kraken publish multi-year candle archives for download; cheaper and more reliable than paging a rate-limited API. Source: [Dropstab free crypto data API](https://news.dropstab.com/research/free-crypto-data-api) — secondary.

7. **Others worth a line:** CoinPaprika free 20k credits a month; Finnhub 60 calls a minute with a 15-minute delay; Twelve Data 800 requests a day; Hyperliquid and Bybit free exchange streams. None changes the picture above. Source: same comparisons; all UNVERIFIED against vendor pages.

8. **Freqtrade** (GPL-3.0) is the established open-source crypto bot framework and already wraps CCXT, backtesting and paper trading; if the bot project is about strategy rather than plumbing, starting there and keeping the strategy code private is allowed (GPL only binds distribution). Source: [freqtrade](https://github.com/freqtrade/freqtrade).

## Not checked

- Binance's current API documentation for exact weights and WebSocket connection limits.
- Whether any of this is allowed under each provider's terms for a bot that places orders; market data and order placement are different agreements.
- EU-specific restrictions on exchanges (MiCA) and on Alpaca account opening from the Netherlands.
- Latency from a Contabo VPS to Binance's endpoints.
