import { createSQLiteThread, createHttpBackend } from 'sqlite-wasm-http';

export async function initConnection() {
  const remoteURL = 'http://127.0.0.1/feeds.db';
  //const remoteURL = 'https://velivole.b-cdn.net/maptiler-osm-2017-07-03-v3.6.1-europe.mbtiles';
  const httpBackend = createHttpBackend({
    //maxPageSize: 1024,
    maxPageSize: 4096,
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

export async function getDomains(dbarg) {
  let db = await dbarg;
  console.log(db);
  let queue = [];
  await db('exec', { // await
    sql: 'SELECT title FROM feeds LIMIT 3',
    // sql: 'SELECT zoom_level FROM tiles LIMIT 3',
    bind: {},
    callback: (msg) => {
      if (msg.row) {
        queue.push(msg.row[0]);
        // console.log(msg.columnNames);
        // console.log(msg.row);
      }
    }
  });
  return queue;
  // db('close', {}); // await
  // db.close();
  // httpBackend.close(); // await
}

export async function getEntries(dbarg, feedid) {
  let db = await dbarg;
  let queue = [];
  await db('exec', { // await
    sql: `SELECT id, title, date, url
          FROM entries
          WHERE feedid=$fid
          LIMIT 3
    `,
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
