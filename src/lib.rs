use std::os::raw::{c_char, c_int};
use std::path::PathBuf;

use rusqlite::{
    ffi,
    Connection, Result, Error
};
use rusqlite::functions::FunctionFlags;
use rusqlite::types::{ToSqlOutput, Value};

pub mod send_conn;

pub mod table_fn;
use table_fn::create_tablefn_module;

mod timer;
mod write_to_file;
mod tcp;

#[expect(clippy::not_unsafe_ptr_arg_deref)]
#[no_mangle]
pub unsafe extern "C" fn sqlite3_extension_init(
    db: *mut ffi::sqlite3,
    pz_err_msg: *mut *mut c_char,
    p_api: *mut ffi::sqlite3_api_routines,
) -> c_int {
    Connection::extension_init2(db, pz_err_msg, p_api, extension_init)
}

fn extension_init(db: Connection) -> Result<bool> {
    db.create_scalar_function(
        "sqlio_version",
        0,
        FunctionFlags::SQLITE_DETERMINISTIC,
        |_ctx| {
            Ok(ToSqlOutput::Owned(Value::Text(
                env!("CARGO_PKG_VERSION").to_string(),
            )))
        },
    )?;
    db.create_scalar_function(
        "read_file",
        1,
        FunctionFlags::empty(),
        |ctx| {
            use std::fs;
            use std::io::Read;

            let path = PathBuf::from(ctx.get::<String>(0)?);
            let mut f = fs::File::options()
                .read(true)
                .open(path)
                .map_err(|e| Error::UserFunctionError(Box::new(e)))?;
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)
                .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

            Ok(buf)
        },
    )?;
    db.create_scalar_function(
        "write_to_file",
        2,
        FunctionFlags::empty(),
        |ctx| {
            use std::fs;
            use std::io::Write;

            let path = PathBuf::from(ctx.get::<String>(0)?);
            let content = ctx.get::<String>(1)?;

            let mut f = fs::File::options()
                .write(true)
                .create(true)
                .open(path)
                .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

            f.write_all(content.as_bytes())
                .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

            Ok(None::<u8>) // return null
        },
    )?;
    db.create_scalar_function(
        "tcp_listen",
        3,
        FunctionFlags::empty(),
        |ctx| {
            let conn = unsafe { ctx.get_connection()? };
            let addr_str = ctx.get::<String>(0)?;
            let connect_cb = ctx.get::<String>(1)?;
            let data_cb = ctx.get::<String>(2)?;

            let addr: std::net::SocketAddr = addr_str.parse()
                .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

            tcp::start_listen(&conn, addr, connect_cb, data_cb)?;

            Ok(None::<u8>) // return null
        },
    )?;
    db.create_scalar_function(
        "tcp_send",
        2,
        FunctionFlags::empty(),
        |ctx| {
            let token_str = ctx.get::<String>(0)?;
            let token: tcp::ConnectionToken = token_str.parse()
                .map_err(|_| Error::ModuleError(format!("Could not parse token {token_str}")))?;
            let data = ctx.get::<Vec<u8>>(1)
                .or_else(|_| ctx.get::<String>(1).map(|s| s.as_bytes().to_vec()))?;

            tcp::send_to(token, &data)?;

            Ok(None::<u8>) // return null
        },
    )?;
    create_tablefn_module::<write_to_file::WriteToFile>(&db)?;
    create_tablefn_module::<timer::Timer>(&db)?;

    rusqlite::trace::log(ffi::SQLITE_WARNING, "sqlio initialized");
    Ok(false)
}
