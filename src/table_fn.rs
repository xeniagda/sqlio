use std::os::raw::c_int;

use rusqlite::{types, vtab, Connection, Result, Error};

/// A cursor for a table of static values
#[repr(C)]
pub struct StaticCursor {
    base: vtab::sqlite3_vtab_cursor,
    values: Vec<Vec<types::Value>>,
    current_row: usize,
}

impl StaticCursor {
    fn from_values(values: Vec<Vec<types::Value>>) -> Self {
        StaticCursor {
            base: vtab::sqlite3_vtab_cursor::default(),
            values,
            current_row: 0,
        }
    }
}

unsafe impl vtab::VTabCursor for StaticCursor {
    fn filter(&mut self, _idx_num: c_int, _idx_str: Option<&str>, _args: &vtab::Values<'_>) -> Result<()> {
        self.current_row = 0;
        Ok(())
    }

    fn next(&mut self) -> Result<()> {
        self.current_row += 1;
        Ok(())
    }

    fn eof(&self) -> bool {
        self.current_row >= self.values.len()
    }

    fn column(&self, ctx: &mut vtab::Context, i: c_int) -> Result<()> {
        ctx.set_result(&self.values[self.current_row][i as usize])
    }

    fn rowid(&self) -> Result<i64> {
        Ok(self.current_row as i64)
    }
}

pub trait TableFn {
    /// Name of the table module
    const MODULE_NAME: &str;
    /// sql syntax for columns of the table
    const FMT: &str; // CREATE TABLE x(...)

    fn new(conn: &mut vtab::VTabConnection) -> Self;

    /// Called whenever `INSERT INTO` is called on the table. args[0] will be 0,
    /// args[1] will be NULL, args[2..] will contain the column values
    fn on_insert(&mut self, args: &vtab::Values) -> Result<()>;

    /// Called whenever a `SELECT ... FROM` is issued
    /// Return a list of rows, each row being a list of values
    fn get(&self) -> Result<Vec<Vec<types::Value>>> {
        Ok(vec![])
    }
}

#[repr(C)]
pub struct TableFnVTab<T: TableFn> {
    base: vtab::sqlite3_vtab,
    inner: T,
}

unsafe impl<'v, T: TableFn> vtab::VTab<'v> for TableFnVTab<T> {
    type Aux = ();

    type Cursor = StaticCursor;

    fn connect(
        db: &mut vtab::VTabConnection,
        _aux: Option<&Self::Aux>,
        _args: &[&[u8]],
    ) -> Result<(String, Self)> {
        Ok((
            T::FMT.to_string(),
            Self {
                base: vtab::sqlite3_vtab::default(),
                inner: T::new(db),
            }
        ))
    }

    fn best_index(&self, info: &mut vtab::IndexInfo) -> Result<()> {
        info.set_estimated_cost(1.);
        Ok(())
    }

    fn open(&'v mut self) -> Result<Self::Cursor> {
        let values = self.inner.get()?;
        Ok(StaticCursor::from_values(values))
    }
}

impl<'v, T: TableFn> vtab::CreateVTab<'v> for TableFnVTab<T> {
    const KIND: vtab::VTabKind = vtab::VTabKind::Eponymous;
}

impl<'v, T: TableFn> vtab::UpdateVTab<'v> for TableFnVTab<T> {
    fn delete(&mut self, _arg: types::ValueRef<'_>) -> Result<()> {
        Err(Error::ModuleError(format!("Can't DELETE FROM {}", T::MODULE_NAME).to_string()))
    }

    fn update(&mut self, _args: &vtab::Values<'_>) -> Result<()> {
        Err(Error::ModuleError(format!("Can't UPDATE {}", T::MODULE_NAME).to_string()))
    }

    fn insert(&mut self, args: &vtab::Values<'_>) -> Result<i64> {
        self.inner.on_insert(args)?;
        Ok(0)
    }
}

pub fn create_tablefn_module<T: TableFn + 'static>(db: &Connection) -> Result<()> {
    db.create_module(
        T::MODULE_NAME,
        vtab::update_module::<TableFnVTab<T>>(),
        None,
    )
}
