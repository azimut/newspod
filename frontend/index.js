import { createSQLiteThread, createHttpBackend } from "sqlite-wasm-http";

export async function initConnection() {
  // const remoteURL = "https://azimut.github.io/newspod/feeds.db";
  // const remoteURL = "http://192.168.100.1/feeds.db";
  // const remoteURL = 'http://127.0.0.1/feeds.db';
  const remoteURL = "../feeds.db.tar.gz";
  const httpBackend = createHttpBackend({
    maxPageSize: 1024,
    timeout: 10000,
    cacheSize: 4096,
  });
  return createSQLiteThread({ http: httpBackend }).then((db) => {
    db("open", {
      filename: "file:" + encodeURI(remoteURL),
      vfs: "http",
    });
    return db;
  });
}

export async function getEntries(dbarg, feedid) {
  let db = await dbarg;
  let queue = [];
  await db("exec", {
    sql: `SELECT id, title, datemillis, url
            FROM entries
           WHERE feedid=$fid
        ORDER BY datemillis DESC`,
    bind: { $fid: feedid },
    callback: (msg) => {
      if (msg.row) {
        let [id, title, date, url] = msg.row;
        queue.push({
          id: id,
          feedid: feedid,
          title: title,
          date: date,
          url: url,
        });
      }
    },
  });
  return queue;
}

export async function search(dbarg, needle) {
  let db = await dbarg;
  let queue = [];
  await db("exec", {
    sql: `SELECT entries.feedid,
                 entries.id,
                 entries.title,
                 entries.url,
                 entries.datemillis
            FROM entries
            JOIN search
              ON search.rowid=entries.id
           WHERE search MATCH $match
        ORDER BY entries.datemillis DESC`,
    bind: { $match: needle },
    callback: (msg) => {
      if (msg.row) {
        let [feedid, entryid, title, url, date] = msg.row;
        queue.push({
          id: entryid,
          feedid: feedid,
          title: title,
          date: date,
          url: url,
        });
      }
    },
  });
  return queue;
}

export async function getFeedDetails(dbarg, feedid) {
  let db = await dbarg;
  let result = {};
  await db("exec", {
    sql: `SELECT fd.home,
                 fd.description,
                 fd.language,
                 fd.image,
                 fd.author,
                 feeds.url
            FROM feeds_details fd
            JOIN feeds ON feeds.id = fd.feedid
           WHERE feeds.id = $id`,
    bind: { $id: feedid },
    callback: (msg) => {
      if (msg.row) {
        let [home, description, language, image, author, url] = msg.row;
        result = {
          id: feedid,
          home: home,
          description: description,
          language: language,
          image: image,
          author: author,
          url: url,
        };
      }
    },
  });
  return result;
}

export async function getEntryDetails(dbarg, entryId, needle) {
  let db = await dbarg;
  let result;
  if (needle && typeof needle === "string" && needle.length > 0) {
    await db("exec", {
      sql: `SELECT entries.feedid, highlight(search,1,'\`\`\`','\`\`\`')
              FROM entries
              JOIN search ON entries.id=search.rowid
             WHERE entries.id=$eid
               AND search MATCH $needle`,
      bind: { $eid: entryId, $needle: needle },
      callback: (msg) => {
        if (msg.row) {
          let [feedid, content] = msg.row;
          result = {
            id: entryId,
            feedid: feedid,
            content: content,
          };
        }
      },
    });
  } else {
    await db("exec", {
      sql: `SELECT entries.feedid, entries_content.description
              FROM entries
              JOIN entries_content ON entries_content.entriesid=entries.id
             WHERE entries.id=$eid`,
      bind: { $eid: entryId },
      callback: (msg) => {
        if (msg.row) {
          let [feedid, content] = msg.row;
          result = {
            id: entryId,
            feedid: feedid,
            content: content,
          };
        }
      },
    });
  }
  return result;
}

// TODO: use it!
export async function db_latest(dbarg) {
  let db = await dbarg;
  let result = [];
  await db("exec", {
    sql: `SELECT id,
                 feedid,
                 title,
                 datemillis,
                 url,
            FROM entries
        ORDER BY datemillis DESC
           LIMIT 20`,
    bind: {},
    callback: (msg) => {
      if (msg.row) {
        let [id, feedid, title, datemillis, url] = msg.row;
        result.push({
          id,
          feedid,
          title,
          datemillis,
          url,
        });
      }
    },
  });
  return result;
}
