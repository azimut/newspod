import { createSQLiteThread, createHttpBackend } from 'sqlite-wasm-http';

export async function initConnection() {
  const remoteURL = 'https://azimut.github.io/newspod/feeds.db';
  // const remoteURL = 'http://127.0.0.1/feeds.db';
  // const remoteURL = "./feeds.db";
  const httpBackend = createHttpBackend({
    maxPageSize: 1024,
    timeout: 10000,
    cacheSize: 4096
  });
  return createSQLiteThread({ http: httpBackend })
    .then((db) => {
      db('open', {
        filename: 'file:' + encodeURI(remoteURL),
        vfs: 'http'
      });
      return db;
    });
}

export async function getFeeds(dbarg) {
  let db = await dbarg;
  let queue = [];
  await db('exec', {
    sql: `SELECT feeds.id, feeds.title, count(*)
            FROM feeds
            JOIN entries
                ON feeds.id=entries.feedid
            JOIN feeds_metadata
                ON feeds.id=feeds_metadata.feedid
        GROUP BY entries.feedid
          HAVING count(*) > 0
        ORDER BY feeds_metadata.lastentry DESC`,
    bind: {},
    callback: (msg) => {
      if (msg.row) {
        let [id,title,count] = msg.row;
        queue.push({
          id: id,
          title: title,
          nEntries: count
        });
      }
    }
  });
  return queue;
}

export async function getEntries(dbarg, feedid) {
  let db = await dbarg;
  let queue = [];
  await db('exec', {
    sql: `SELECT id, title, datemillis, url
            FROM entries
           WHERE feedid=$fid
        ORDER BY datemillis DESC`,
    bind: {$fid: feedid},
    callback: (msg) => {
      if (msg.row) {
        let [id,title,date,url] = msg.row;
        queue.push({
          id: id,
          feedid: feedid,
          title: title,
          date: date,
          url: url
        });
      }
    }
  });
  return queue;
}

export async function search(dbarg, needle) {
  let db = await dbarg;
  let queue = [];
  await db('exec', {
    sql: `SELECT entries.feedid,
                 entries.id,
                 entries.title,
                 entries.url,
                 entries.datemillis
            FROM search
            JOIN entries ON search.entriesid=entries.id
           WHERE search MATCH $match
           ORDER BY entries.datemillis DESC`,
    bind: {$match: needle},
    callback: (msg) => {
      if (msg.row) {
        let [feedid,entryid,title,url,date] = msg.row;
        queue.push({
          id: entryid,
          feedid: feedid,
          title: title,
          date: date,
          url: url
        });
      }
    }
  });
  return queue;
}

export async function getEntryDetails(dbarg, entryId, needle) {
  let db = await dbarg;
  let result;
  if (needle && typeof needle === "string" && needle.length > 0) {
    await db('exec', {
      sql: `SELECT entries.feedid, highlight(search,2,'\`\`\`','\`\`\`')
              FROM entries
              JOIN search ON entries.id=search.entriesid
             WHERE entries.id=$eid
               AND search MATCH $needle`,
      bind: {$eid: entryId, $needle: needle},
      callback: (msg) => {
        if (msg.row) {
          let [feedid,content] = msg.row;
          result = {
            id: entryId,
            feedid: feedid,
            content: content
          };
        }
      }
    });
  } else {
    await db('exec', {
      sql: `SELECT entries.feedid, entries_content.content
              FROM entries
              JOIN entries_content ON entries_content.entriesid=entries.id
             WHERE entries.id=$eid`,
      bind: {$eid: entryId},
      callback: (msg) => {
        if (msg.row) {
          let [feedid,content] = msg.row;
          result = {
            id: entryId,
            feedid: feedid,
            content: content
          };
        }
      }
    });
  }
  return result;
}

export async function db_stats(dbarg) {
  let db = await dbarg;
  let result = 0;
  await db('exec', {
    sql: `SELECT *
            FROM (SELECT COUNT(1) FROM feeds)
            JOIN (SELECT COUNT(1) FROM entries)
            JOIN (SELECT page_size*page_count FROM pragma_page_count(), pragma_page_size())`,
    bind: {},
    callback: (msg) => {
      if (msg.row) {
        let [nfeeds, nentries, size] = msg.row;
        result = {
          nPodcasts: nfeeds,
          nEntries: nentries,
          dbSize: size,
        };
      }
    }
  });
  return result;
}
