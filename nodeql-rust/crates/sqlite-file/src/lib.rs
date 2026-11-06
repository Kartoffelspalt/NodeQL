//! Read SQLite b-trees from a stable database image without a SQLite runtime.
//!
//! This API exposes physical records. Use a SQLite connection for SQL column
//! semantics, virtual tables, views, or a snapshot of a live database.

use std::{
    collections::HashSet,
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom},
    ops::ControlFlow,
    path::{Path, PathBuf},
    time::SystemTime,
};

const MAGIC: &[u8; 16] = b"SQLite format 3\0";
const HEADER_SIZE: usize = 100;
const MAX_DEPTH: usize = 64;
const MAX_FIELDS: usize = 32_767;

#[derive(Debug)]
pub enum Error {
    Io(io::Error),
    Invalid(&'static str),
    Unstable,
    RecordLimit,
    TableNotFound,
    NoStoredRecords,
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, output: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => error.fmt(output),
            Self::Invalid(message) => write!(output, "Invalid SQLite image: {message}"),
            Self::Unstable => output.write_str(
                "SQLite image changed or has a pending journal. Use a consistent snapshot.",
            ),
            Self::RecordLimit => {
                output.write_str("SQLite record exceeds the configured size limit.")
            }
            Self::TableNotFound => output.write_str("Table not found in sqlite_schema."),
            Self::NoStoredRecords => {
                output.write_str("This object has no ordinary stored table records.")
            }
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub page_size: usize,
    pub usable_page_size: usize,
    pub page_count: u32,
    pub encoding: Encoding,
    pub schema_format: u32,
    pub user_version: u32,
    pub application_id: u32,
    pub write_version: u8,
    pub read_version: u8,
}

impl Header {
    /// Inspect the main-file header. It can lag behind an active WAL.
    pub fn read(path: &Path) -> Result<Option<Self>, Error> {
        if !fs::metadata(path)?.is_file() {
            return Err(Error::Invalid("expected a regular file"));
        }
        let mut file = File::open(path)?;
        let metadata = file.metadata()?;
        if !metadata.is_file() {
            return Err(Error::Invalid("expected a regular file"));
        }
        if metadata.len() == 0 {
            return Ok(None);
        }
        read_header(&mut file, metadata.len()).map(|(header, _)| Some(header))
    }
}

fn read_header(file: &mut File, size: u64) -> Result<(Header, [u8; HEADER_SIZE]), Error> {
    if size < HEADER_SIZE as u64 {
        return Err(Error::Invalid("truncated header"));
    }
    let mut bytes = [0; HEADER_SIZE];
    file.seek(SeekFrom::Start(0))?;
    file.read_exact(&mut bytes)?;
    if &bytes[..MAGIC.len()] != MAGIC {
        return Err(Error::Invalid("unrecognized header"));
    }
    let encoded_size = be16(&bytes[16..]);
    let page_size = if encoded_size == 1 {
        65_536
    } else {
        usize::from(encoded_size)
    };
    if !(512..=65_536).contains(&page_size)
        || !page_size.is_power_of_two()
        || !size.is_multiple_of(page_size as u64)
        || !matches!(bytes[18], 1 | 2)
        || !matches!(bytes[19], 1 | 2)
        || bytes[21..24] != [64, 32, 32]
    {
        return Err(Error::Invalid("invalid page size or format version"));
    }
    let usable_page_size = page_size - usize::from(bytes[20]);
    if usable_page_size < 480 {
        return Err(Error::Invalid("invalid reserved region"));
    }
    let physical_count = u32::try_from(size / page_size as u64)
        .map_err(|_| Error::Invalid("page count overflow"))?;
    let stored_count = be32(&bytes[28..]);
    let page_count = if stored_count != 0 && bytes[24..28] == bytes[92..96] {
        stored_count
    } else {
        physical_count
    };
    if page_count > physical_count {
        return Err(Error::Invalid("truncated page data"));
    }
    let schema_format = be32(&bytes[44..]);
    let encoding = match be32(&bytes[56..]) {
        0 if schema_format == 0 => Encoding::Utf8,
        1 => Encoding::Utf8,
        2 => Encoding::Utf16Le,
        3 => Encoding::Utf16Be,
        _ => return Err(Error::Invalid("unknown text encoding")),
    };
    if schema_format > 4 {
        return Err(Error::Invalid("unknown schema format"));
    }
    Ok((
        Header {
            page_size,
            usable_page_size,
            page_count,
            encoding,
            schema_format,
            user_version: be32(&bytes[60..]),
            application_id: be32(&bytes[68..]),
            write_version: bytes[18],
            read_version: bytes[19],
        },
        bytes,
    ))
}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Integer(i64),
    Real(f64),
    Text(String),
    Blob(Vec<u8>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Record {
    pub rowid: Option<i64>,
    /// Physical field order, with INTEGER PRIMARY KEY aliases stored as NULL.
    pub fields: Vec<Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectKind {
    Table,
    Index,
    View,
    Trigger,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SchemaEntry {
    pub kind: ObjectKind,
    pub name: String,
    pub table: String,
    pub root_page: u32,
    pub definition: Option<String>,
}

pub struct Image {
    file: File,
    path: PathBuf,
    header: Header,
    header_bytes: [u8; HEADER_SIZE],
    size: u64,
    modified: Option<SystemTime>,
    max_record_bytes: usize,
}

impl Image {
    /// Open a stable, checkpointed image. A nonempty WAL or rollback journal
    /// requires a snapshot through the live reader. This API acquires no SQL locks.
    pub fn open(path: &Path) -> Result<Self, Error> {
        let path = path.canonicalize()?;
        check_sidecars(&path)?;
        if !fs::metadata(&path)?.is_file() {
            return Err(Error::Invalid("expected a regular file"));
        }
        let mut file = File::open(&path)?;
        let metadata = file.metadata()?;
        if !metadata.is_file() {
            return Err(Error::Invalid("expected a regular file"));
        }
        let size = metadata.len();
        let (header, header_bytes) = read_header(&mut file, size)?;
        let mut image = Self {
            file,
            path,
            header,
            header_bytes,
            size,
            modified: metadata.modified().ok(),
            max_record_bytes: 16 * 1024 * 1024,
        };
        image.check_stable()?;
        Ok(image)
    }

    pub fn header(&self) -> Header {
        self.header
    }

    pub fn set_max_record_bytes(&mut self, bytes: usize) {
        self.max_record_bytes = bytes;
    }

    pub fn schema(&mut self) -> Result<Vec<SchemaEntry>, Error> {
        let mut entries = Vec::new();
        let mut invalid = None;
        self.visit_root(1, |record| {
            match schema_entry(record) {
                Ok(entry) => entries.push(entry),
                Err(error) => {
                    invalid = Some(error);
                    return ControlFlow::Break(());
                }
            }
            ControlFlow::Continue(())
        })?;
        if let Some(error) = invalid {
            return Err(error);
        }
        Ok(entries)
    }

    /// Visit physical records in key order. A `WITHOUT ROWID` table returns
    /// primary-key fields first. An error means the caller must discard results.
    pub fn visit_table(
        &mut self,
        name: &str,
        visit: impl FnMut(Record) -> ControlFlow<()>,
    ) -> Result<(), Error> {
        let entry = self
            .schema()?
            .into_iter()
            .find(|entry| {
                matches!(entry.kind, ObjectKind::Table | ObjectKind::View)
                    && entry.name.eq_ignore_ascii_case(name)
            })
            .ok_or(Error::TableNotFound)?;
        if entry.root_page == 0 {
            return Err(Error::NoStoredRecords);
        }
        self.visit_root(entry.root_page, visit)
    }

    pub fn visit_root(
        &mut self,
        root: u32,
        mut visit: impl FnMut(Record) -> ControlFlow<()>,
    ) -> Result<(), Error> {
        self.check_stable()?;
        let mut walk = Walker {
            image: self,
            seen: HashSet::new(),
            index: None,
            visit: &mut visit,
        };
        let _ = walk.tree(root, 0)?;
        self.check_stable()
    }

    fn check_stable(&mut self) -> Result<(), Error> {
        check_sidecars(&self.path)?;
        let meta = self.file.metadata()?;
        let current = fs::metadata(&self.path)?;
        if meta.len() != self.size
            || meta.modified().ok() != self.modified
            || current.len() != self.size
            || current.modified().ok() != self.modified
        {
            return Err(Error::Unstable);
        }
        let mut bytes = [0; HEADER_SIZE];
        self.file.seek(SeekFrom::Start(0))?;
        self.file.read_exact(&mut bytes)?;
        if bytes != self.header_bytes {
            return Err(Error::Unstable);
        }
        Ok(())
    }

    fn page(&mut self, number: u32) -> Result<Vec<u8>, Error> {
        if number == 0 || number > self.header.page_count {
            return Err(Error::Invalid("page outside database"));
        }
        let start = u64::from(number - 1) * self.header.page_size as u64;
        let mut page = vec![0; self.header.usable_page_size];
        self.file.seek(SeekFrom::Start(start))?;
        self.file.read_exact(&mut page)?;
        Ok(page)
    }
}

fn check_sidecars(path: &Path) -> Result<(), Error> {
    for suffix in ["-wal", "-journal"] {
        let mut sidecar = path.as_os_str().to_os_string();
        sidecar.push(suffix);
        match fs::metadata(sidecar) {
            Ok(meta) if meta.len() != 0 => return Err(Error::Unstable),
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

struct Walker<'a, F> {
    image: &'a mut Image,
    seen: HashSet<u32>,
    index: Option<bool>,
    visit: &'a mut F,
}

impl<F: FnMut(Record) -> ControlFlow<()>> Walker<'_, F> {
    fn page(&mut self, number: u32) -> Result<Vec<u8>, Error> {
        if !self.seen.insert(number) {
            return Err(Error::Invalid("reused b-tree or overflow page"));
        }
        self.image.page(number)
    }

    fn tree(&mut self, number: u32, depth: usize) -> Result<ControlFlow<()>, Error> {
        if depth >= MAX_DEPTH {
            return Err(Error::Invalid("b-tree too deep"));
        }
        let page = self.page(number)?;
        let base = if number == 1 { HEADER_SIZE } else { 0 };
        let tag = page[base];
        let (index, interior) = match tag {
            2 => (true, true),
            5 => (false, true),
            10 => (true, false),
            13 => (false, false),
            _ => return Err(Error::Invalid("unexpected b-tree page type")),
        };
        if number == 1 && index {
            return Err(Error::Invalid("schema is not a table b-tree"));
        }
        if *self.index.get_or_insert(index) != index {
            return Err(Error::Invalid("inconsistent b-tree page type"));
        }
        let count = usize::from(be16(&page[base + 3..]));
        let start = base + if interior { 12 } else { 8 };
        let end = start + count * 2;
        let pointers = page
            .get(start..end)
            .ok_or(Error::Invalid("truncated cell pointers"))?;
        let mut used = HashSet::with_capacity(count);
        for pointer in pointers.as_chunks::<2>().0 {
            let offset = usize::from(be16(pointer));
            if offset < end || offset >= page.len() || !used.insert(offset) {
                return Err(Error::Invalid("invalid cell pointer"));
            }
            let mut cell = &page[offset..];
            if interior {
                let child = take(&mut cell, 4)?;
                if self.tree(be32(child), depth + 1)?.is_break() {
                    return Ok(ControlFlow::Break(()));
                }
            }
            if index || !interior {
                let record = self.record(cell, index)?;
                if (self.visit)(record).is_break() {
                    return Ok(ControlFlow::Break(()));
                }
            }
        }
        if interior {
            return self.tree(be32(&page[base + 8..]), depth + 1);
        }
        Ok(ControlFlow::Continue(()))
    }

    fn record(&mut self, mut cell: &[u8], index: bool) -> Result<Record, Error> {
        let length = usize::try_from(varint(&mut cell)?).map_err(|_| Error::RecordLimit)?;
        if length > self.image.max_record_bytes || length > i32::MAX as usize {
            return Err(Error::RecordLimit);
        }
        let rowid = if index {
            None
        } else {
            Some(varint(&mut cell)? as i64)
        };
        let usable = self.image.header.usable_page_size;
        let max_local = if index {
            (usable - 12) * 64 / 255 - 23
        } else {
            usable - 35
        };
        let min_local = (usable - 12) * 32 / 255 - 23;
        if length <= max_local {
            return decode_record(take(&mut cell, length)?, rowid, self.image.header.encoding);
        }
        let candidate = min_local + (length - min_local) % (usable - 4);
        let local = if candidate <= max_local {
            candidate
        } else {
            min_local
        };
        let local_bytes = take(&mut cell, local)?;
        let mut overflow = be32(take(&mut cell, 4)?);
        let mut payload = Vec::new();
        payload
            .try_reserve_exact(length)
            .map_err(|_| Error::RecordLimit)?;
        payload.extend_from_slice(local_bytes);
        while payload.len() < length {
            let page = self.page(overflow)?;
            overflow = be32(&page);
            let chunk = (length - payload.len()).min(usable - 4);
            payload.extend_from_slice(&page[4..4 + chunk]);
        }
        if overflow != 0 {
            return Err(Error::Invalid("overflow chain longer than payload"));
        }
        decode_record(&payload, rowid, self.image.header.encoding)
    }
}

fn decode_record(payload: &[u8], rowid: Option<i64>, encoding: Encoding) -> Result<Record, Error> {
    let mut types = payload;
    let size = usize::try_from(varint(&mut types)?).map_err(|_| Error::RecordLimit)?;
    let prefix = payload.len() - types.len();
    let rest = size
        .checked_sub(prefix)
        .ok_or(Error::Invalid("invalid record header length"))?;
    let mut fields = take(&mut types, rest)?;
    let mut body = types;
    let mut values = Vec::new();
    while !fields.is_empty() {
        if values.len() == MAX_FIELDS {
            return Err(Error::RecordLimit);
        }
        let serial = varint(&mut fields)?;
        let value = match serial {
            0 => Value::Null,
            1..=6 => {
                let bytes = take(&mut body, [1, 2, 3, 4, 6, 8][serial as usize - 1])?;
                let mut signed = [if bytes[0] & 0x80 == 0 { 0 } else { 0xff }; 8];
                signed[8 - bytes.len()..].copy_from_slice(bytes);
                Value::Integer(i64::from_be_bytes(signed))
            }
            7 => Value::Real(f64::from_be_bytes(take(&mut body, 8)?.try_into().unwrap())),
            8 => Value::Integer(0),
            9 => Value::Integer(1),
            10 | 11 => return Err(Error::Invalid("reserved record serial type")),
            other => {
                let bytes = take(
                    &mut body,
                    usize::try_from((other - 12) / 2).map_err(|_| Error::RecordLimit)?,
                )?;
                if other.is_multiple_of(2) {
                    Value::Blob(bytes.to_vec())
                } else {
                    Value::Text(decode_text(bytes, encoding)?)
                }
            }
        };
        values.push(value);
    }
    if !body.is_empty() {
        return Err(Error::Invalid("unconsumed record bytes"));
    }
    Ok(Record {
        rowid,
        fields: values,
    })
}

fn decode_text(bytes: &[u8], encoding: Encoding) -> Result<String, Error> {
    if encoding == Encoding::Utf8 {
        return Ok(String::from_utf8_lossy(bytes).into_owned());
    }
    if !bytes.len().is_multiple_of(2) {
        return Err(Error::Invalid("misaligned UTF-16"));
    }
    let words = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            if encoding == Encoding::Utf16Le {
                u16::from_le_bytes([pair[0], pair[1]])
            } else {
                be16(pair)
            }
        })
        .collect::<Vec<_>>();
    Ok(String::from_utf16_lossy(&words))
}

fn schema_entry(record: Record) -> Result<SchemaEntry, Error> {
    let [
        Value::Text(kind),
        Value::Text(name),
        Value::Text(table),
        page,
        definition,
    ]: [Value; 5] = record
        .fields
        .try_into()
        .map_err(|_| Error::Invalid("invalid sqlite_schema record"))?
    else {
        return Err(Error::Invalid("invalid sqlite_schema field types"));
    };
    let kind = match kind.as_str() {
        "table" => ObjectKind::Table,
        "index" => ObjectKind::Index,
        "view" => ObjectKind::View,
        "trigger" => ObjectKind::Trigger,
        _ => return Err(Error::Invalid("unknown sqlite_schema object")),
    };
    let definition = match definition {
        Value::Null => None,
        Value::Text(sql) => Some(sql),
        _ => return Err(Error::Invalid("invalid schema definition")),
    };
    let root_page = match page {
        Value::Integer(page) => {
            u32::try_from(page).map_err(|_| Error::Invalid("invalid schema root"))?
        }
        Value::Null if kind != ObjectKind::Index => 0,
        _ => return Err(Error::Invalid("invalid schema root")),
    };
    Ok(SchemaEntry {
        kind,
        name,
        table,
        root_page,
        definition,
    })
}

fn varint(bytes: &mut &[u8]) -> Result<u64, Error> {
    let mut value = 0;
    for _ in 0..8 {
        let byte = take(bytes, 1)?[0];
        value = (value << 7) | u64::from(byte & 0x7f);
        if byte & 0x80 == 0 {
            return Ok(value);
        }
    }
    Ok((value << 8) | u64::from(take(bytes, 1)?[0]))
}

fn take<'a>(bytes: &mut &'a [u8], length: usize) -> Result<&'a [u8], Error> {
    let (head, tail) = bytes
        .split_at_checked(length)
        .ok_or(Error::Invalid("truncated cell or record"))?;
    *bytes = tail;
    Ok(head)
}

fn be16(bytes: &[u8]) -> u16 {
    u16::from_be_bytes([bytes[0], bytes[1]])
}
fn be32(bytes: &[u8]) -> u32 {
    u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}
