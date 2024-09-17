use std::{
    net,
    thread,
    sync::{LazyLock, Arc, RwLock},
    collections::HashMap,
    io::{Read, Write},
};

use rusqlite::{types, Connection, Result, Error};
use rand::{Rng, thread_rng, distributions};

use crate::send_conn::ConnectionThreadWrapper;

#[derive(PartialEq, Eq, Hash, Clone)]
pub struct ConnectionToken(u32);
impl distributions::Distribution<ConnectionToken> for distributions::Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> ConnectionToken {
        ConnectionToken(rng.gen())
    }
}
impl std::fmt::Display for ConnectionToken {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:08x}", self.0)
    }
}

impl std::str::FromStr for ConnectionToken {
    type Err = ();

    fn from_str(s: &str) -> std::prelude::v1::Result<Self, Self::Err> {
        u32::from_str_radix(s, 16)
            .map_err(|_| ())
            .map(ConnectionToken)
    }
}


pub struct TcpConnection {
    remote_addr: net::SocketAddr,
    stream: net::TcpStream,
}

static OPEN_CONNECTIONS: LazyLock<Arc<RwLock<HashMap<ConnectionToken, TcpConnection>>>> = LazyLock::new(|| {
    Arc::new(RwLock::new(HashMap::new()))
});

/// Callback in form
/// INSERT INTO connect_cb (token, remote_addr) VALUES (..)
/// INSERT INTO data_cb (token, byte) VALUES (..) -- byte is an integer 0-255
pub fn start_listen(
    conn: &Connection,
    local_addr: net::SocketAddr,
    connect_cb: String,
    data_cb: String,
) -> Result<()> {
    let listener = net::TcpListener::bind(local_addr)
        .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

    let connw = ConnectionThreadWrapper::from_connection(conn);

    thread::spawn(move || {
        let conn = connw.to_connection();
        let mut rng = thread_rng();
        let mut connect_cb_stmt = conn.prepare(
            &format!("INSERT INTO {connect_cb} (token, remote_addr) VALUES (?, ?)"),
        ).expect("Could not prepare connect callback statement");
        loop {
            let (stream, remote_addr) = match listener.accept() {
                Ok(x) => x,
                Err(e) => {
                    eprintln!("Failed to accept on {local_addr}: {e}");
                    break;
                }
            };
            let listen_stream = stream.try_clone().expect("could not clone the stream");

            let mut connections = OPEN_CONNECTIONS.write().expect("OPEN_CONNECTIONS poisoned");
            let token = loop {
                let token = rng.gen();
                if connections.contains_key(&token) { continue; }
                break token;
            };
            eprintln!("[log] new connection {token} = {remote_addr}");
            connections.insert(token.clone(), TcpConnection { remote_addr: remote_addr.clone(), stream });
            std::mem::drop(connections);

            connect_cb_stmt
                .execute(&[&format!("{token}"), &format!("{remote_addr}")])
                .expect("Could not insert new connection into database");

            let connw = connw.clone();
            let data_cb = data_cb.clone();
            thread::spawn(move || {
                let conn = connw.to_connection();
                start_communication(
                    conn,
                    token,
                    listen_stream,
                    data_cb,
                );
            });
        }
    });

    Ok(())
}

fn start_communication(
    conn: Connection,
    token: ConnectionToken,
    mut listen_stream: net::TcpStream,
    data_cb: String,
) {
    let mut data_cb_stmt = conn.prepare(
        &format!("INSERT INTO {data_cb} (token, byte) VALUES (?, ?)"),
    ).expect("Could not prepare data callback statement");
    loop {
        let mut buf = [0u8];
        listen_stream.read_exact(&mut buf)
            .expect("Could not read from socket");

        data_cb_stmt.execute(&[
            &types::Value::Text(format!("{}", token)),
            &types::Value::Integer(buf[0] as i64)
        ])
            .expect("Could not execute callback for data");
    }
}

pub fn send_to(
    token: ConnectionToken,
    data: &[u8],
) -> Result<()> {
    let mut connections = OPEN_CONNECTIONS.write().expect("OPEN_CONNECTIONS got poisoned");
    let connection = connections.get_mut(&token)
        .ok_or(Error::ModuleError(format!("unknown token {token}")))?;

    connection.stream.write_all(data)
        .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

    Ok(())
}
