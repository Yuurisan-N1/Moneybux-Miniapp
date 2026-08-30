<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=Money%20Bux%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Daily%20Check-in%20%7C%20Spin%20Wheel%20%7C%20Treasury%20%7C%20Raiders%20%7C%20Multi-Account&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Auto+Daily+Check-in+%7C+Claim+Gold+%26+Diamonds;Auto+Spin+Wheel+%7C+Collect+Ad+Spins+%26+Spin+All;Auto+Treasury+%7C+Collect+Ad+Keys+%26+Open+All+Chests;Auto+Raiders+%7C+Collect+Ad+Raid+Passes;Games+Detected+Dynamically+from+Server"/>

<p>
  <img alt="python" src="https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-Money%20Bux%20Miniapp-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>Money Bux Bot</b> is a full automation bot for the Money Bux Telegram Miniapp.<br/>
  It handles the complete daily cycle: claiming the daily check-in, then automatically detecting and playing all available games. For Spin Wheel it collects all available ad spins then spins until none remain. For Treasury it collects all available ad keys then opens all chests. For Raiders it collects all available ad raid passes. All game slugs are detected dynamically from the server so new games are picked up automatically.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Python `3.10+`
- Git

---

## Installation

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Moneybux-Miniapp.git
cd Moneybux-Miniapp
```

**Install dependencies:**

```bash
pip install aiohttp beautifulsoup4 colorama
```

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with Telegram WebApp `initData` for each account, one per line:

```
user=%7B%22id%22...&hash=abc123
user=%7B%22id%22...&hash=def456
```

> `initData` can be obtained from the browser DevTools when opening Money Bux on Telegram Web.

### 2. Bot Settings (config.json)

`sleep_seconds` controls how many seconds the bot waits between cycles.

---

## Running the Bot

```bash
python bot.py
```

Press `Ctrl+C` at any time to stop the bot cleanly.

---

## Features

### Daily Check-in
The bot submits the daily check-in claim for each account. If successful, it logs the Gold and Diamonds received. If already claimed today or not yet available, it is skipped silently.

### Dynamic Game Detection
Before processing games, the bot fetches the live game list from the server by parsing the game navigation buttons from the HTML response. Only valid game slugs are processed. If the fetch fails, it falls back to the default set of Wheel, Treasury, and Raiders. New games added server-side are picked up automatically without any code changes.

### Auto Spin Wheel
The bot fetches the current Spin Wheel state, reads how many ads have been watched today against the cap of 50, and collects all remaining ad reward slots. Each slot gets a validation hash, builds a signed payload, and submits the claim. After all ad spins are collected, the bot spins the wheel one by one until no spins remain. Each spin logs the Gold earned and spins remaining.

### Auto Treasury
The bot fetches the current Treasury state, reads how many ads have been watched today against the cap of 50, and collects all remaining ad key reward slots using the same signed payload flow. After all ad keys are collected, the bot opens chests one by one until no keys remain. Each chest logs the loot amount, Gold, Diamonds, and keys remaining.

### Auto Raiders
The bot fetches the current Raiders state, reads how many ads have been watched today against the cap of 50, and collects all remaining ad raid pass reward slots. Each claim logs the Gold earned and ads watched. Raiders has no secondary action after collecting passes.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Gold and Diamonds balance are logged at the start of each account. The cycle number is tracked and logged at the start of each round.

### Auto Countdown
After all accounts complete a cycle, the bot displays a live `HH:MM:SS` countdown until the next cycle starts.

---

## File Structure

```text
Moneybux-Miniapp/
├── bot.py          # Main bot, full daily cycle automation
├── config.json     # Sleep duration between cycles
├── data.txt        # Account initData, one per line
├── LICENSE         # License file
└── utils/
    └── banner.py   # Banner display on startup
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>