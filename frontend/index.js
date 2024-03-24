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
            FROM feeds JOIN entries ON feeds.id=entries.feedid
        GROUP BY entries.feedid
          HAVING count(*) > 0`,
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
    sql: `SELECT id, title, date, url
          FROM entries
          WHERE feedid=$fid`,
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
