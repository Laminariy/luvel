---------------------------------------------------------------------------
-- A LevelDB wrapper for LuaJIT and Luvit
-- MIT License
-- Copyright(c) 2022 Xiejiangzhi
-- Copyright(c) 2022 Ravener
-- Original library: https://github.com/Codezerker/lua_leveldb
---------------------------------------------------------------------------
--
--[[lit-meta
  name = "ravener/luvel"
  version = "0.0.2"
  dependencies = {}
  description = "A LevelDB wrapper for LuaJIT and Luvit"
  tags = { "leveldb", "database", "ffi" }
  license = "MIT"
  author = { name = "Ravener", email = "ravener.anime@gmail.com" }
  homepage = "https://github.com/ravener/luvel"
]]
local ffi = require("ffi")
local leveldb = ffi.load("leveldb")

local DB = {}
DB.__index = DB

local Iterator = {}
Iterator.__index = Iterator

local WriteBatch = {}
WriteBatch.__index = WriteBatch

-- Ref https://github.com/google/leveldb/blob/master/include/leveldb/c.h
ffi.cdef[[
  typedef struct leveldb_t leveldb_t;
  typedef struct leveldb_options_t leveldb_options_t;
  typedef struct leveldb_iterator_t leveldb_iterator_t;
  typedef struct leveldb_readoptions_t leveldb_readoptions_t;
  typedef struct leveldb_writebatch_t leveldb_writebatch_t;
  typedef struct leveldb_writeoptions_t leveldb_writeoptions_t;

  leveldb_t* leveldb_open(const leveldb_options_t* options, const char* name, char** errptr);
  void leveldb_destroy_db(const leveldb_options_t* options, const char* name, char** errptr);
  void leveldb_repair_db(const leveldb_options_t* options, const char* name, char** errptr);
  void leveldb_close(leveldb_t* db);
  void leveldb_free(void* ptr);
  int leveldb_major_version();
  int leveldb_minor_version();

  void leveldb_put(
    leveldb_t* db, const leveldb_writeoptions_t* options,
    const char* key, size_t keylen, const char* val, size_t vallen,
    char** errptr
  );
  void leveldb_delete(
    leveldb_t* db, const leveldb_writeoptions_t* options,
    const char* key, size_t keylen,
    char** errptr
  );
  void leveldb_write(
    leveldb_t* db, const leveldb_writeoptions_t* options,
    leveldb_writebatch_t* batch, char** errptr
  );
  char* leveldb_get(
    leveldb_t* db, const leveldb_readoptions_t* options,
    const char* key, size_t keylen, size_t* vallen, char** errptr
  );

  leveldb_iterator_t* leveldb_create_iterator(leveldb_t* db, const leveldb_readoptions_t* options);
  void leveldb_iter_destroy(leveldb_iterator_t*);

  unsigned char leveldb_iter_valid(const leveldb_iterator_t*);
  void leveldb_iter_seek_to_first(leveldb_iterator_t*);
  void leveldb_iter_seek_to_last(leveldb_iterator_t*);
  void leveldb_iter_seek(leveldb_iterator_t*, const char* k, size_t klen);
  void leveldb_iter_next(leveldb_iterator_t*);
  void leveldb_iter_prev(leveldb_iterator_t*);
  const char* leveldb_iter_key(const leveldb_iterator_t*, size_t* klen);
  const char* leveldb_iter_value(const leveldb_iterator_t*, size_t* vlen);
  void leveldb_iter_get_error(const leveldb_iterator_t*, char** errptr);

  leveldb_writebatch_t* leveldb_writebatch_create();
  void leveldb_writebatch_destroy(leveldb_writebatch_t*);
  void leveldb_writebatch_put(
    leveldb_writebatch_t*,
    const char* key, size_t klen, const char* val, size_t vlen
  );
  void leveldb_writebatch_delete(leveldb_writebatch_t*, const char* key, size_t klen);

  leveldb_options_t* leveldb_options_create();
  void leveldb_options_destroy(leveldb_options_t*);
  void leveldb_options_set_create_if_missing(leveldb_options_t*, uint8_t);
  void leveldb_options_set_error_if_exists(leveldb_options_t*, uint8_t);
  void leveldb_options_set_compression(leveldb_options_t*, int);
  void leveldb_options_set_paranoid_checks(leveldb_options_t*, uint8_t);

  leveldb_readoptions_t* leveldb_readoptions_create();
  void leveldb_readoptions_destroy(leveldb_readoptions_t*);

  leveldb_writeoptions_t* leveldb_writeoptions_create();
  void leveldb_writeoptions_destroy(leveldb_writeoptions_t*);
]]

local function T_open(obj)
  if obj._closed then
    error("Object is closed.")
  end
end

local function create_options_with(options, fn)
  local c_options = leveldb.leveldb_options_create()
  local c_err = ffi.new("char*[1]")

  options = options or {}

  if options.createIfMissing ~= nil then
    leveldb.leveldb_options_set_create_if_missing(c_options, options.createIfMissing)
  end

  if options.errorIfExists ~= nil then
    leveldb.leveldb_options_set_error_if_exists(c_options, options.errorIfExists)
  end

  if options.compression ~= nil then
    leveldb.leveldb_options_set_compression(c_options, options.compression)
  end

  if options.paranoidChecks ~= nil then
    leveldb.leveldb_options_set_paranoid_checks(c_options, options.paranoid_checks)
  end

  local r = fn(c_options, c_err)
  leveldb.leveldb_options_destroy(c_options)
  if c_err[0] ~= nil then error(ffi.string(c_err[0])) end

  return r
end

local function create_read_options_with(options, fn)
  local c_options = leveldb.leveldb_readoptions_create()
  local c_err = ffi.new("char*[1]")

  local r = fn(c_options, c_err)
  leveldb.leveldb_readoptions_destroy(c_options)
  if c_err[0] ~= nil then error(ffi.string(c_err[0])) end

  return r
end

local function create_write_options_with(sync, fn)
  local c_options = leveldb.leveldb_writeoptions_create()
  local c_err = ffi.new("char*[1]")

  if sync ~= nil then
    leveldb.leveldb_writeoptions_set_sync(c_options, sync)
  end

  local r = fn(c_options, c_err)
  leveldb.leveldb_writeoptions_destroy(c_options)
  if c_err[0] ~= nil then error(ffi.string(c_err[0])) end

  return r
end


local function open(dirname, options)
  local db = setmetatable({}, DB)

  create_options_with(options, function(c_options, c_err)
    db._db = leveldb.leveldb_open(c_options, dirname, c_err)
  end)

  return db
end

local function version()
  return leveldb.leveldb_major_version(), leveldb.leveldb_minor_version()
end

function DB:put(key, val, sync) T_open(self)
  create_write_options_with(sync, function(c_options, c_err)
    leveldb.leveldb_put(self._db, c_options, key, #key, val, #val, c_err)
  end)
end

function DB:batchPut(data, options) T_open(self)
  if type(data) ~= "table" then error("data is not a table.") end

  local batch = WriteBatch.new(self._db)
  for key, val in pairs(data) do batch:put(key, val) end
  batch:write(options)
  batch:destroy()
end

function DB:get(key, options) T_open(self)
  return create_read_options_with(options, function(c_options, c_err)
    local c_size = ffi.new("size_t[1]")
    local c_result = leveldb.leveldb_get(self._db, c_options, key, #key, c_size, c_err)

    if c_size[0] == 0 then
      return nil
    else
      return ffi.string(c_result, c_size[0])
    end
  end)
end

function DB:del(key, sync) T_open(self)
  create_write_options_with(sync, function(c_options, c_err)
    leveldb.leveldb_delete(self._db, c_options, key, #key, c_err)
  end)
end

-- Params:
--  data: it's a array, example {'a', 'b', 'c'}
--
function DB:batchDel(data, options) T_open(self)
  if type(data) ~= "table" then error("data is not table.") end

  local batch = WriteBatch.new(self._db)
  for _, key in ipairs(data) do batch:del(key) end
  batch:write(options)
  batch:destroy()
end

function DB:newIteratorWith(options, fn) T_open(self)
  local iter = Iterator.new(self._db, options)
  fn(iter)
  iter:destroy()
end

-- fn(options, function(k, v, iter))
function DB:each(options, fn) T_open(self)
  local iter = Iterator.new(self._db, options)
  iter:first()
  local tmp
  for k, v in iter.next, iter do
    tmp = fn(k, v, iter)
    if tmp == false then break end
  end
  iter:destroy()
end

function DB:batch() T_open(self)
  return WriteBatch.new(self._db)
end

function DB:close() T_open(self)
  leveldb.leveldb_close(self._db)
  self._closed = true
end

function DB:__gc()
  if not self._closed then self:close() end
end

local function destroy(dirname)
  create_options_with({}, function (c_options, c_err)
    leveldb.leveldb_destroy_db(c_options, dirname, c_err)
  end)
end

local function repair(dirname)
  create_options_with({}, function (c_options, c_err)
    leveldb.leveldb_repair_db(c_options, dirname, c_err)
  end)
end


--
-- Iterator operations --
--

function Iterator.new(db, options)
  local iter = setmetatable({}, Iterator)

  iter.db = db
  create_read_options_with(options, function(c_options)
    iter.iterator = leveldb.leveldb_create_iterator(iter.db, c_options)
  end)

  return iter
end

function Iterator:first() T_open(self)
  leveldb.leveldb_iter_seek_to_first(self.iterator)
end

function Iterator:last() T_open(self)
  leveldb.leveldb_iter_seek_to_last(self.iterator)
end

function Iterator:seek(key) T_open(self)
  leveldb.leveldb_iter_seek(self.iterator, key, #key)
end

function Iterator:next() T_open(self)
  local valid = leveldb.leveldb_iter_valid(self.iterator)
  if valid == 0 then return nil end

  local key, value = self:read()
  leveldb.leveldb_iter_next(self.iterator)

  return key, value
end

function Iterator:prev() T_open(self)
  local valid = leveldb.leveldb_iter_valid(self.iterator)
  if valid == 0 then return nil end

  local key, value = self:read()
  leveldb.leveldb_iter_prev(self.iterator)

  return key, value
end

function Iterator:read() T_open(self)
  local valid = leveldb.leveldb_iter_valid(self.iterator)
  if valid == 0 then return nil end

  local c_key_size = ffi.new("size_t[1]")
  local c_key = leveldb.leveldb_iter_key(self.iterator, c_key_size)
  local key = ffi.string(c_key, c_key_size[0])

  local c_value_size = ffi.new("size_t[1]")
  local c_value = leveldb.leveldb_iter_value(self.iterator, c_value_size)
  local value = ffi.string(c_value, c_value_size[0])

  return key, value
end

function Iterator:destroy() T_open(self)
  leveldb.leveldb_iter_destroy(self.iterator)
  self._closed = true
end

function Iterator:__gc()
  if not self._closed then self:destroy() end
end

--
-- Batch operations --
--

function WriteBatch.new(db)
  local batch = setmetatable({}, WriteBatch)

  batch.db = db
  batch.c_batch = leveldb.leveldb_writebatch_create()

  return batch
end

function WriteBatch:put(key, val) T_open(self)
  leveldb.leveldb_writebatch_put(self.c_batch, key, #key, val, #val)
end

function WriteBatch:del(key) T_open(self)
  leveldb.leveldb_writebatch_delete(self.c_batch, key, #key)
end

function WriteBatch:write(sync) T_open(self)
  create_write_options_with(sync, function(c_options, c_err)
    leveldb.leveldb_write(self.db, c_options, self.c_batch, c_err)
  end)
end

function WriteBatch:destroy() T_open(self)
  leveldb.leveldb_writebatch_destroy(self.c_batch)
  self._closed = true
end

function WriteBatch:__gc()
  if not self._closed then self:destroy() end
end

return {
  open = open,
  version = version,
  destroy = destroy,
  repair = repair
}
