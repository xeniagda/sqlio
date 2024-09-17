use rusqlite::{types, vtab, Result};
use crate::send_conn::ConnectionThreadWrapper;

use crate::table_fn::TableFn;

pub struct Timer {
    conn: ConnectionThreadWrapper,
}

impl TableFn for Timer {
    const MODULE_NAME: &str = "timer";

    const FMT: &str = "CREATE TABLE x(n_millis INTEGER, insert_table VARCHAR, value ANY)";

    fn new(conn: &mut vtab::VTabConnection) -> Self {
        Self { conn: ConnectionThreadWrapper::from_vtab_connection(conn) }
    }

    fn on_insert(&mut self, args: &vtab::Values) -> Result<()> {
        use std::thread;
        use std::time::Duration;

        let millis: u64 = args.get(2)?;
        let table_name: String = args.get(3)?;
        let value: types::Value = args.get(4)?;
        let conn = self.conn;

        thread::spawn(move || {
            thread::sleep(Duration::from_millis(millis));
            let db_conn = conn.to_connection();

            match db_conn.execute(&format!("INSERT INTO {} VALUES (?)", table_name), &[&value]) {
                Ok(_n) => {}
                Err(e) => {
                    eprintln!("Could not run timer callback, {e:?}");
                }
            }
        });

        Ok(())
    }
}
