# newspod

From a list of RSS feeds. Generates a static site where you can perform full text searches of the podcast episodes.

<p float="left" align="middle">
    <a href="static/Screenshot_2025-07-17_at_02-52-38_newspod.png">
        <img src="static/Screenshot_2025-07-17_at_02-52-38_newspod.png" width="200" />
    </a>
    <a href="static/Screenshot_2025-09-25_at_21-41-32_newspod.png">
        <img src="static/Screenshot_2025-09-25_at_21-41-32_newspod.png" width="100" />
    </a>
</p>

## Features

- Search and navigation can be filtered by a feed category
- Backed by a SQLite database.
- SQL pagination for entries on a feed.
- Full text search.
- Update daily through *GitHub Actions*.

## Why?

I want to have quick access to podcasts in my phone. But I cannot use/don't care about using an app.

## Build your own!

It should be possible to host your own podcast feed. Just fork and change `feeds.json` with the feeds that YOU want to keep track of. Of course you can also PR if you found a really an interesting podcast I should keep track of (preferably but not limited to tech related stuff).
