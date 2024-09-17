use rusqlite::{vtab, Result, Error};

use crate::table_fn::TableFn;

pub struct WriteToFile;

impl TableFn for WriteToFile {
    const MODULE_NAME: &str = "write_to_file";

    const FMT: &str = "CREATE TABLE x(contents BLOB, path VARCHAR, ty VARCAHR)";

    fn new(_conn: &mut vtab::VTabConnection) -> Self {
        Self {}
    }

    fn on_insert(&mut self, args: &vtab::Values) -> Result<()> {
        use std::fs;
        use std::path::PathBuf;
        use std::io::Write;

        let contents: Vec<u8> = args.get::<Vec<u8>>(2)
            .or_else(|_| args.get::<String>(2).map(|x| x.bytes().collect()))?;

        let path = PathBuf::from(args.get::<String>(3)?);
        let ty: String = args.get(4)?;

        let mut open_options = fs::File::options();
        match &*ty {
            "write" => {
                open_options.create(true).write(true).truncate(true);
            }
            "append" => {
                open_options.create(true).append(true);
            }
            _ => {
                return Err(Error::ModuleError("Argument ty must be either 'write' or 'append'".to_string()))
            }
        };
        let mut f = open_options.open(path)
            .map_err(|e| Error::UserFunctionError(Box::new(e)))?;
        f.write(&contents)
            .map_err(|e| Error::UserFunctionError(Box::new(e)))?;

        Ok(())
    }
}

