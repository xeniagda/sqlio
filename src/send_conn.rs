use rusqlite::{ffi, vtab, Connection};

// Wrapper to send sqlite3 pointers between threads
#[derive(Clone, Copy)]
pub struct ConnectionThreadWrapper(pub *mut ffi::sqlite3);
unsafe impl Send for ConnectionThreadWrapper {}

impl ConnectionThreadWrapper {
    pub fn from_ptr(ptr: *mut ffi::sqlite3) -> Self {
        ConnectionThreadWrapper(ptr)
    }
    pub fn from_connection(conn: &Connection) -> Self {
        ConnectionThreadWrapper(unsafe { conn.handle() })
    }
    pub fn from_vtab_connection(conn: &mut vtab::VTabConnection) -> Self {
        ConnectionThreadWrapper(unsafe { conn.handle() })
    }
    pub fn to_connection(&self) -> Connection {
        unsafe {
            Connection::from_handle(self.0) // can't produce an Err
        }.unwrap()
    }
}
